/// A Core Audio object id for a device (same width as `AudioObjectID`).
public typealias DeviceID = UInt32

/// An output device as the router sees it.
public struct OutputDevice: Equatable, Sendable {
    public let id: DeviceID
    public let name: String

    public init(id: DeviceID, name: String) {
        self.id = id
        self.name = name
    }
}

/// Something changed in the audio hardware. Events carry no state: the router re-reads the provider.
public enum DeviceEvent: Equatable, Sendable {
    /// A device appeared or disappeared (`kAudioHardwarePropertyDevices`).
    case devicesChanged
    /// The system default output changed (`kAudioHardwarePropertyDefaultOutputDevice`).
    case defaultOutputChanged
    /// A device's alive state changed (`kAudioDevicePropertyDeviceIsAlive`).
    case aliveChanged(DeviceID)
    /// A device's nominal sample rate changed (`kAudioDevicePropertyNominalSampleRate`).
    case sampleRateChanged(DeviceID)
    /// The Mac woke from sleep (`NSWorkspace.didWakeNotification`).
    case didWake
}

/// Read access to the audio hardware, plus change events. Implementations deliver `onEvent` on the main actor.
@MainActor
public protocol DeviceProvider: AnyObject {
    func outputDevices() -> [OutputDevice]
    func defaultOutputDevice() -> DeviceID?
    func isAlive(_ id: DeviceID) -> Bool
    func nominalSampleRate(_ id: DeviceID) -> Double?
    var onEvent: ((DeviceEvent) -> Void)? { get set }
}
