import AudioToolbox
import CoreAudio
import Foundation

/// Captures the audio of specific processes through a Core Audio process tap.
///
/// Shape: a `CATapDescription` for the listed processes (never a global tap), wrapped in a private aggregate
/// device whose clock is `clockDeviceUID`, read with an IOProc. The aggregate's input buffers are the clock
/// device's own input buffers first, then the tap's buffers (`tapBufferRange`).
///
/// Teardown is always the full chain in reverse: stop IO, destroy the IOProc, destroy the aggregate, destroy the
/// tap. `rebuild()` runs that teardown and creates everything again with a fresh tap UUID; it is the recovery for
/// a tap that keeps delivering all-zero buffers (see `SilenceWatchdog`).
@available(macOS 14.4, *)
public final class ProcessTapCapture: @unchecked Sendable {
    public struct Configuration: Sendable {
        public var processes: [AudioObjectID]
        public var muteBehavior: CATapMuteBehavior
        /// UID of the real device that clocks the aggregate. Its output buffers are left untouched (silent).
        public var clockDeviceUID: String
        public var name: String

        public init(processes: [AudioObjectID], muteBehavior: CATapMuteBehavior, clockDeviceUID: String,
                    name: String = "Resonance Tap") {
            self.processes = processes
            self.muteBehavior = muteBehavior
            self.clockDeviceUID = clockDeviceUID
            self.name = name
        }
    }

    public typealias InputHandler = @Sendable (UnsafePointer<AudioBufferList>, UnsafePointer<AudioTimeStamp>) -> Void

    public let configuration: Configuration
    public private(set) var tapID = AudioObjectID(kAudioObjectUnknown)
    public private(set) var aggregateID = AudioObjectID(kAudioObjectUnknown)
    public private(set) var tapFormat: AudioStreamBasicDescription?
    /// Indices of the tap's buffers in the aggregate's input buffer list.
    public private(set) var tapBufferRange: Range<Int> = 0..<0
    /// Indices of the clock device's own input buffers in the aggregate's input buffer list.
    public private(set) var clockBufferRange: Range<Int> = 0..<0
    public private(set) var isRunning = false

    private var procID: AudioDeviceIOProcID?
    private var handler: InputHandler?
    private var queue: DispatchQueue?

    public init(configuration: Configuration) {
        precondition(!configuration.processes.isEmpty, "A process tap needs at least one process; a global tap is not allowed here.")
        self.configuration = configuration
    }

    deinit { teardown() }

    /// Creates the tap and its aggregate device without starting IO.
    public func create() throws {
        guard tapID == kAudioObjectUnknown else { return }
        let description = CATapDescription(stereoMixdownOfProcesses: configuration.processes)
        description.uuid = UUID()
        description.name = configuration.name
        description.isPrivate = true
        description.muteBehavior = configuration.muteBehavior

        var newTap = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(description, &newTap), "AudioHardwareCreateProcessTap")
        tapID = newTap
        do {
            tapFormat = try CoreAudioObjects.read(tapID, kAudioTapPropertyFormat, initial: AudioStreamBasicDescription())
            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey: configuration.name,
                kAudioAggregateDeviceUIDKey: "resonance.tap.\(UUID().uuidString)",
                kAudioAggregateDeviceMainSubDeviceKey: configuration.clockDeviceUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: configuration.clockDeviceUID]],
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true,
                ]],
            ]
            var newAggregate = AudioObjectID(kAudioObjectUnknown)
            try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &newAggregate),
                      "AudioHardwareCreateAggregateDevice")
            aggregateID = newAggregate

            let buffers = try CoreAudioObjects.bufferChannelCounts(of: aggregateID, scope: kAudioObjectPropertyScopeInput)
            let clockDevice = try CoreAudioObjects.device(withUID: configuration.clockDeviceUID)
            let clockBuffers = try clockDevice.map {
                try CoreAudioObjects.bufferChannelCounts(of: $0, scope: kAudioObjectPropertyScopeInput).count
            } ?? 0
            clockBufferRange = 0..<min(clockBuffers, buffers.count)
            tapBufferRange = clockBufferRange.upperBound..<buffers.count
        } catch {
            teardown()
            throw error
        }
    }

    /// Creates the tap if needed and starts reading it. `onInput` runs on `queue` for every IO cycle.
    public func start(queue: DispatchQueue, onInput: @escaping InputHandler) throws {
        try create()
        guard !isRunning else { return }
        self.handler = onInput
        self.queue = queue
        var newProc: AudioDeviceIOProcID?
        do {
            try check(AudioDeviceCreateIOProcIDWithBlock(&newProc, aggregateID, queue) { _, input, inputTime, _, _ in
                onInput(input, inputTime)
            }, "AudioDeviceCreateIOProcIDWithBlock")
            procID = newProc
            try check(AudioDeviceStart(aggregateID, procID), "AudioDeviceStart")
        } catch {
            teardown()
            throw error
        }
        isRunning = true
    }

    /// Stops IO and destroys the IOProc, the aggregate device and the tap, in that order.
    public func stop() { teardown() }

    /// Full teardown, then the same tap again with a fresh UUID, restarted with the last handler if it was running.
    public func rebuild() throws {
        let wasRunning = isRunning
        let lastHandler = handler
        let lastQueue = queue
        teardown()
        if wasRunning, let lastHandler, let lastQueue {
            try start(queue: lastQueue, onInput: lastHandler)
        } else {
            try create()
        }
    }

    /// The mute behavior Core Audio reports for the live tap.
    public func appliedMuteBehavior() throws -> CATapMuteBehavior {
        var address = CoreAudioObjects.address(kAudioTapPropertyDescription)
        var value: Unmanaged<CATapDescription>?
        var size = UInt32(MemoryLayout<Unmanaged<CATapDescription>?>.size)
        try check(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &value), "read tap description")
        guard let description = value?.takeRetainedValue() else {
            throw CoreAudioError("read tap description (nil)", kAudioHardwareUnknownPropertyError)
        }
        return description.muteBehavior
    }

    private func teardown() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                if isRunning { AudioDeviceStop(aggregateID, procID) }
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        procID = nil
        isRunning = false
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        tapFormat = nil
        tapBufferRange = 0..<0
        clockBufferRange = 0..<0
    }
}
