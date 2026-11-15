import AppKit
import CoreAudio

/// `DeviceProvider` backed by the Core Audio HAL. Read-only: it never sets a property on any device.
///
/// System-wide it listens to the device list and the default output. Per device it listens to alive state and nominal
/// sample rate, but only on the current default output: the listeners move when the default changes.
@MainActor
public final class CoreAudioDeviceProvider: DeviceProvider {
    public var onEvent: ((DeviceEvent) -> Void)?

    private let system = AudioObjectID(kAudioObjectSystemObject)
    private var systemListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var watchedDevice: AudioObjectID = 0
    private var deviceListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var wakeObserver: NSObjectProtocol?

    public init() {
        addSystemListener(kAudioHardwarePropertyDevices) { [weak self] in
            self?.rewatchDefault()
            self?.onEvent?(.devicesChanged)
        }
        addSystemListener(kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in
            self?.rewatchDefault()
            self?.onEvent?(.defaultOutputChanged)
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.rewatchDefault()
                self?.onEvent?(.didWake)
            }
        }
        rewatchDefault()
    }

    /// Removes every listener. Call before dropping the provider; the blocks hold `self` weakly, so a missed call
    /// leaves only inert listeners behind.
    public func invalidate() {
        for (address, block) in systemListeners {
            var a = address
            AudioObjectRemovePropertyListenerBlock(system, &a, DispatchQueue.main, block)
        }
        systemListeners = []
        unwatchDevice()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        onEvent = nil
    }

    // MARK: DeviceProvider

    public func outputDevices() -> [OutputDevice] {
        var address = Self.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter(hasOutputStreams).map { OutputDevice(id: $0, name: name(of: $0) ?? "Unknown Device") }
    }

    public func defaultOutputDevice() -> DeviceID? {
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        var id: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
        return id
    }

    public func isAlive(_ id: DeviceID) -> Bool {
        var address = Self.address(kAudioDevicePropertyDeviceIsAlive)
        var alive: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &alive) == noErr && alive != 0
    }

    public func nominalSampleRate(_ id: DeviceID) -> Double? {
        var address = Self.address(kAudioDevicePropertyNominalSampleRate)
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &rate) == noErr ? rate : nil
    }

    // MARK: Listeners

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    /// Wraps a handler for delivery on the main queue (the HAL calls blocks on the queue they were registered with).
    private static func block(_ handler: @escaping @MainActor () -> Void) -> AudioObjectPropertyListenerBlock {
        { _, _ in MainActor.assumeIsolated { handler() } }
    }

    private func addSystemListener(_ selector: AudioObjectPropertySelector, _ handler: @escaping @MainActor () -> Void) {
        var address = Self.address(selector)
        let block = Self.block(handler)
        if AudioObjectAddPropertyListenerBlock(system, &address, DispatchQueue.main, block) == noErr {
            systemListeners.append((address, block))
        }
    }

    private func rewatchDefault() {
        let id = defaultOutputDevice() ?? 0
        guard id != watchedDevice else { return }
        unwatchDevice()
        guard id != 0 else { return }
        watchedDevice = id
        for selector in [kAudioDevicePropertyDeviceIsAlive, kAudioDevicePropertyNominalSampleRate] {
            var address = Self.address(selector)
            let block = Self.block { [weak self] in
                guard let self else { return }
                self.onEvent?(selector == kAudioDevicePropertyDeviceIsAlive ? .aliveChanged(id) : .sampleRateChanged(id))
            }
            if AudioObjectAddPropertyListenerBlock(id, &address, DispatchQueue.main, block) == noErr {
                deviceListeners.append((address, block))
            }
        }
    }

    private func unwatchDevice() {
        for (address, block) in deviceListeners {
            var a = address
            AudioObjectRemovePropertyListenerBlock(watchedDevice, &a, DispatchQueue.main, block)
        }
        deviceListeners = []
        watchedDevice = 0
    }

    // MARK: Device properties

    private func hasOutputStreams(_ id: AudioObjectID) -> Bool {
        var address = Self.address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private func name(of id: AudioObjectID) -> String? {
        var address = Self.address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }
}
