import CoreAudio

/// What the capture side reports to the silence watchdog.
public struct CaptureHealth: Equatable, Sendable {
    /// Whether any non-zero buffer arrived since this tap was created.
    public var signalSeen: Bool
    /// Length of the current run of exactly-zero buffers, in seconds.
    public var silentSeconds: Double
    /// Whether any captured process is running audio output right now. Lets the watchdog tell a stale tap (zeros while
    /// something plays) from a pause (zeros because nothing plays). Only meaningful during a run of zeros; `true` when
    /// unknown, so an unreadable process list falls back to the capped rebuilds.
    public var othersPlaying: Bool

    public init(signalSeen: Bool, silentSeconds: Double, othersPlaying: Bool = true) {
        self.signalSeen = signalSeen
        self.silentSeconds = silentSeconds
        self.othersPlaying = othersPlaying
    }
}

/// The capture side: a process tap in a private aggregate device, writing into the buffer from its IOProc.
@MainActor
public protocol CaptureSource: AnyObject {
    /// Creates the tap and its aggregate without starting IO. Returns the capture sample rate.
    func prepare() throws -> Double
    /// Starts IO into `buffer` (prepares first if needed).
    func start(into buffer: DriftCompensatedBuffer) throws
    /// Stops IO and destroys the IOProc, the aggregate and the tap.
    func stop()
    /// Full teardown, a fresh tap, IO restarted into the same buffer. Returns the new capture rate.
    func rebuild() throws -> Double
    var isRunning: Bool { get }
    /// The tap's sample rate as Core Audio reports it now, or nil when there is no tap.
    func currentSampleRate() -> Double?
    func currentHealth() -> CaptureHealth
}

/// The output side: pitch shift and playback on one device, reading the buffer from its render callback.
@MainActor
public protocol OutputSink: AnyObject {
    /// Plays on `deviceID`. `clientSampleRate` is the buffer's rate; the output converts to the device's rate.
    func start(deviceID: DeviceID, clientSampleRate: Double, buffer: DriftCompensatedBuffer, pitchCents: Float) throws
    func stop()
    func setPitchCents(_ cents: Float)
    var isRunning: Bool { get }
}

/// What the engine is doing. Drives the menu.
public enum EngineState: Equatable, Sendable {
    case off
    /// Shifting, playing on this device.
    case running(DeviceID)
    /// No usable output device right now: nothing is tapped.
    case waitingForOutput
    /// Stopped by an error. When it happened during a device change, the next change retries.
    case failed(String)
}

/// The `i`-th buffer of an AudioBufferList, by raw offset. Real-time safe, unlike
/// `UnsafeMutableAudioBufferListPointer`, whose generic collection code calls into the Swift runtime.
@inline(__always)
func audioBuffer(_ list: UnsafePointer<AudioBufferList>, _ index: Int) -> AudioBuffer {
    let offset = MemoryLayout<AudioBufferList>.size - MemoryLayout<AudioBuffer>.size
    return (UnsafeRawPointer(list) + offset).assumingMemoryBound(to: AudioBuffer.self)[index]
}
