import Foundation

/// Runs the shift: capture (process tap) → `DriftCompensatedBuffer` → output (NewTimePitch on the current default
/// output), and keeps it bound to what the `DeviceRouter` says.
///
/// Order rules (HQ-433 step 0, `docs/research/2026-11-16/tap-spike.md`): the tap mutes what it captures (`muted`),
/// so the output starts first and the tap is created last, and nothing stays tapped while the output is down.
///
/// - Rebind (default output or its rate changed): only the output restarts, on the same buffer. If the tap's own
///   rate changed with it, everything restarts.
/// - Headset profile (≤ 24 kHz): both sides stop; audio plays untouched until the rate goes back up.
/// - Output lost: both sides stop until the router names a usable output.
/// - Wake: both sides restart from scratch (a fresh tap), since sleep is when taps go stale.
/// - Silence watchdog: when a tap that has delivered audio turns to exact zeros for `silentSecondsBeforeRebuild`, the
///   tap is rebuilt once. The new tap waits for its own first signal, so paused music does not cause a rebuild loop.
@MainActor
public final class ShiftEngine {
    public static let watchdogInterval = 0.5
    public static let silentSecondsBeforeRebuild = 3.0
    /// With no signal at all this long after start, the menu says how to check the capture permission.
    public static let noSignalNoticeAfter = 6.0
    public static let noSignalNotice = "Nothing captured yet. If music is playing and you hear nothing, allow Resonance in System Settings › Privacy & Security › Screen & System Audio Recording."

    public private(set) var state: EngineState = .off {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    /// A non-fatal hint for the menu, or nil.
    public private(set) var notice: String? {
        didSet { if notice != oldValue { onNoticeChange?(notice) } }
    }
    public var onStateChange: ((EngineState) -> Void)?
    public var onNoticeChange: ((String?) -> Void)?
    public private(set) var pitchCents: Float = PitchMode.hz432.pitchCents

    private let capture: CaptureSource
    private let output: OutputSink
    private let router: DeviceRouter
    private let scheduler: RouterScheduler
    private let makeBufferConfig: (Double) -> DriftBufferConfig
    private var buffer: DriftCompensatedBuffer?
    private var watchdog: ScheduledTask?
    private var secondsWithoutAnySignal = 0.0
    private var everSawSignal = false
    private var capturePrepared = false
    /// The tap's rate last time, used as the output's first client rate so a restart usually starts it once.
    private var lastTapRate: Double?

    public init(capture: CaptureSource, output: OutputSink, router: DeviceRouter, scheduler: RouterScheduler,
                bufferConfig: @escaping (Double) -> DriftBufferConfig = { DriftBufferConfig(sampleRate: $0) }) {
        self.capture = capture
        self.output = output
        self.router = router
        self.scheduler = scheduler
        self.makeBufferConfig = bufferConfig
        router.onRebind = { [weak self] target in self?.routerRebind(target) }
        router.onOutputLost = { [weak self] in self?.routerLost() }
        router.onHealthCheck = { [weak self] target in self?.routerWake(target) }
    }

    public var isActive: Bool { state != .off }

    /// Turns the shift on. Throws (and leaves everything stopped) if the first start fails.
    public func start() throws {
        guard state == .off || isFailed else { return }
        everSawSignal = false
        secondsWithoutAnySignal = 0
        notice = nil
        guard let target = router.start() else {
            state = .waitingForOutput
            return
        }
        do {
            try apply(target)
        } catch {
            stopIO()
            router.stop()
            state = .failed(Self.message(error))
            throw error
        }
    }

    public func stop() {
        router.stop()
        stopIO()
        notice = nil
        state = .off
    }

    public func setPitchCents(_ cents: Float) {
        pitchCents = cents
        if output.isRunning { output.setPitchCents(cents) }
    }

    // MARK: Router events

    private func routerRebind(_ target: OutputTarget) {
        guard state != .off else { return }
        perform { try apply(target) }
    }

    private func routerLost() {
        guard state != .off else { return }
        stopIO()
        state = .waitingForOutput
    }

    private func routerWake(_ target: OutputTarget?) {
        guard case .running = state, let target, !target.isHeadsetProfile else { return }
        perform {
            stopIO()
            try startIO(target)
        }
    }

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
        } catch {
            stopIO()
            state = .failed(Self.message(error))
        }
    }

    // MARK: IO

    private func apply(_ target: OutputTarget) throws {
        if target.isHeadsetProfile {
            stopIO()
            state = .pausedHeadset
        } else if capture.isRunning, let buffer {
            try rebindOutput(target, buffer: buffer)
        } else {
            try startIO(target)
        }
    }

    private func startIO(_ target: OutputTarget) throws {
        let guessRate = lastTapRate ?? target.sampleRate
        var buffer = DriftCompensatedBuffer(config: makeBufferConfig(guessRate))
        try output.start(deviceID: target.deviceID, clientSampleRate: guessRate, buffer: buffer,
                         pitchCents: pitchCents)
        capturePrepared = true
        let tapRate = try capture.prepare()
        lastTapRate = tapRate
        if tapRate != guessRate {
            buffer = DriftCompensatedBuffer(config: makeBufferConfig(tapRate))
            output.stop()
            try output.start(deviceID: target.deviceID, clientSampleRate: tapRate, buffer: buffer, pitchCents: pitchCents)
        }
        try capture.start(into: buffer)
        self.buffer = buffer
        state = .running(target.deviceID)
        scheduleWatchdog()
    }

    private func rebindOutput(_ target: OutputTarget, buffer: DriftCompensatedBuffer) throws {
        output.stop()
        try output.start(deviceID: target.deviceID, clientSampleRate: buffer.config.sampleRate, buffer: buffer,
                         pitchCents: pitchCents)
        if let live = capture.currentSampleRate(), live != buffer.config.sampleRate {
            lastTapRate = live
            stopIO()
            try startIO(target)
            return
        }
        state = .running(target.deviceID)
    }

    private func stopIO() {
        watchdog?.cancel()
        watchdog = nil
        if capture.isRunning || capturePrepared { capture.stop() }
        capturePrepared = false
        if output.isRunning { output.stop() }
        buffer = nil
    }

    // MARK: Watchdog

    private func scheduleWatchdog() {
        watchdog?.cancel()
        watchdog = scheduler.schedule(after: Self.watchdogInterval) { [weak self] in self?.pollWatchdog() }
    }

    private func pollWatchdog() {
        guard case .running = state, capture.isRunning else { return }
        let health = capture.currentHealth()
        if health.signalSeen {
            everSawSignal = true
            notice = nil
            if health.silentSeconds >= Self.silentSecondsBeforeRebuild {
                perform {
                    let rate = try capture.rebuild()
                    if let buffer, rate != buffer.config.sampleRate, let target = router.current {
                        stopIO()
                        try startIO(target)
                    }
                }
            }
        } else if !everSawSignal {
            secondsWithoutAnySignal += Self.watchdogInterval
            if secondsWithoutAnySignal >= Self.noSignalNoticeAfter { notice = Self.noSignalNotice }
        }
        if case .running = state { scheduleWatchdog() }
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    static func message(_ error: Error) -> String {
        if let error = error as? LocalizedError, let text = error.errorDescription { return text }
        return String(describing: error)
    }
}
