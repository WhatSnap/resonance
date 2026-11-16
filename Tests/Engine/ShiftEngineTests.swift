import Testing
@testable import ResonanceCore

// MARK: - Fakes

/// Shared call log, so tests can assert the order of capture and output calls.
@MainActor
final class CallLog {
    var calls: [String] = []
}

@MainActor
final class FakeCapture: CaptureSource {
    let log: CallLog
    var rate: Double = 48_000
    var liveRate: Double?
    var failPrepare: Error?
    var health = CaptureHealth(signalSeen: false, silentSeconds: 0)
    private(set) var isRunning = false
    private(set) var prepareCount = 0
    private(set) var startCount = 0
    private(set) var rebuildCount = 0
    private(set) var buffer: DriftCompensatedBuffer?

    init(log: CallLog) { self.log = log }

    func prepare() throws -> Double {
        log.calls.append("capture.prepare")
        prepareCount += 1
        if let failPrepare { throw failPrepare }
        return rate
    }

    func start(into buffer: DriftCompensatedBuffer) throws {
        log.calls.append("capture.start")
        startCount += 1
        self.buffer = buffer
        isRunning = true
    }

    func stop() {
        log.calls.append("capture.stop")
        isRunning = false
        health = CaptureHealth(signalSeen: false, silentSeconds: 0)
    }

    func rebuild() throws -> Double {
        log.calls.append("capture.rebuild")
        rebuildCount += 1
        health = CaptureHealth(signalSeen: false, silentSeconds: 0)
        return rate
    }

    func currentSampleRate() -> Double? { liveRate ?? (isRunning ? rate : nil) }
    func currentHealth() -> CaptureHealth { health }
}

@MainActor
final class FakeOutput: OutputSink {
    struct Start: Equatable {
        let deviceID: DeviceID
        let clientSampleRate: Double
        let pitchCents: Float
    }

    let log: CallLog
    var failStart: Error?
    private(set) var isRunning = false
    private(set) var starts: [Start] = []
    private(set) var stopCount = 0
    private(set) var pitch: Float?

    init(log: CallLog) { self.log = log }

    func start(deviceID: DeviceID, clientSampleRate: Double, buffer: DriftCompensatedBuffer, pitchCents: Float) throws {
        log.calls.append("output.start")
        if let failStart { throw failStart }
        starts.append(Start(deviceID: deviceID, clientSampleRate: clientSampleRate, pitchCents: pitchCents))
        pitch = pitchCents
        isRunning = true
    }

    func stop() {
        log.calls.append("output.stop")
        stopCount += 1
        isRunning = false
    }

    func setPitchCents(_ cents: Float) { pitch = cents }
}

struct FakeError: Error, CustomStringConvertible {
    let description: String
}

@MainActor
struct EngineHarness {
    let provider = FakeDeviceProvider()
    let clock = FakeScheduler()
    let log = CallLog()
    let capture: FakeCapture
    let output: FakeOutput
    let router: DeviceRouter
    let engine: ShiftEngine

    init(devices: [FakeDeviceProvider.Device] = [speakers, airPods], default id: DeviceID? = speakers.id) {
        provider.deviceList = devices
        provider.defaultOutput = id
        capture = FakeCapture(log: log)
        output = FakeOutput(log: log)
        router = DeviceRouter(provider: provider, scheduler: clock)
        engine = ShiftEngine(capture: capture, output: output, router: router, scheduler: clock)
    }

    func settle() { clock.advance(by: 1.0) }
}

// MARK: - Tests

@MainActor
@Suite("ShiftEngine")
struct ShiftEngineTests {

    @Test("start: output first, then the tap is created, then capture IO starts")
    func startOrder() throws {
        let h = EngineHarness()
        try h.engine.start()
        #expect(h.log.calls == ["output.start", "capture.prepare", "capture.start"])
        #expect(h.engine.state == .running(speakers.id))
        #expect(h.output.starts == [.init(deviceID: speakers.id, clientSampleRate: 48_000, pitchCents: PitchMode.hz432.pitchCents)])
    }

    @Test("a tap at another rate restarts the output at the tap's rate before capture starts")
    func tapRateWins() throws {
        let h = EngineHarness()
        h.capture.rate = 44_100
        try h.engine.start()
        #expect(h.log.calls == ["output.start", "capture.prepare", "output.stop", "output.start", "capture.start"])
        #expect(h.output.starts.last?.clientSampleRate == 44_100)
        #expect(h.capture.buffer?.config.sampleRate == 44_100)
    }

    @Test("a rebind restarts only the output, on the same buffer")
    func rebindIsOutputOnly() throws {
        let h = EngineHarness()
        try h.engine.start()
        let buffer = h.capture.buffer
        h.log.calls = []
        h.provider.setDefault(airPods.id)
        h.settle()
        #expect(h.log.calls == ["output.stop", "output.start"])
        #expect(h.capture.startCount == 1 && h.capture.prepareCount == 1)
        #expect(h.output.starts.last?.deviceID == airPods.id)
        #expect(h.capture.buffer === buffer)
        #expect(h.engine.state == .running(airPods.id))
    }

    @Test("a rebind where the tap's live rate changed does a full restart")
    func rebindWithTapRateChange() throws {
        let h = EngineHarness()
        try h.engine.start()
        h.capture.liveRate = 44_100
        h.capture.rate = 44_100
        h.log.calls = []
        h.provider.setDefault(airPods.id)
        h.settle()
        #expect(h.log.calls == ["output.stop", "output.start", "capture.stop", "output.stop",
                                "output.start", "capture.prepare", "capture.start"])
        #expect(h.capture.buffer?.config.sampleRate == 44_100)
    }

    @Test("headset profile pauses the shift and the next normal rate resumes it, output first")
    func headsetPauseAndResume() throws {
        let h = EngineHarness()
        try h.engine.start()
        h.log.calls = []
        h.provider.setRate(speakers.id, 16_000)
        h.settle()
        #expect(h.engine.state == .pausedHeadset)
        #expect(!h.capture.isRunning && !h.output.isRunning)
        #expect(h.log.calls == ["capture.stop", "output.stop"])

        h.log.calls = []
        h.provider.setRate(speakers.id, 48_000)
        h.settle()
        #expect(h.engine.state == .running(speakers.id))
        #expect(h.log.calls == ["output.start", "capture.prepare", "capture.start"])
    }

    @Test("starting while the output is in the headset profile starts paused, with nothing tapped")
    func startInHeadsetProfile() throws {
        let headset = FakeDeviceProvider.Device(id: 21, name: "AirPods (call)", sampleRate: 24_000)
        let h = EngineHarness(devices: [headset], default: headset.id)
        try h.engine.start()
        #expect(h.engine.state == .pausedHeadset)
        #expect(h.log.calls.isEmpty)
    }

    @Test("output lost stops everything and waits; the next output resumes")
    func outputLostWaits() throws {
        let h = EngineHarness(devices: [airPods], default: airPods.id)
        try h.engine.start()
        h.provider.disconnect(airPods.id)
        h.provider.setDefault(nil)
        h.settle()
        #expect(h.engine.state == .waitingForOutput)
        #expect(!h.capture.isRunning && !h.output.isRunning)

        h.provider.connect(speakers)
        h.provider.setDefault(speakers.id)
        h.settle()
        #expect(h.engine.state == .running(speakers.id))
        #expect(h.capture.isRunning && h.output.isRunning)
    }

    @Test("starting with no output waits instead of failing")
    func startWithoutOutput() throws {
        let h = EngineHarness(devices: [], default: nil)
        try h.engine.start()
        #expect(h.engine.state == .waitingForOutput)
        #expect(h.log.calls.isEmpty)
    }

    @Test("wake rebuilds capture and output from scratch")
    func wakeRestarts() throws {
        let h = EngineHarness()
        try h.engine.start()
        h.log.calls = []
        h.provider.wake()
        h.settle()
        #expect(h.log.calls == ["capture.stop", "output.stop", "output.start", "capture.prepare", "capture.start"])
        #expect(h.engine.state == .running(speakers.id))
    }

    @Test("all-zero buffers after a signal rebuild the tap once, then wait for a signal again")
    func silenceWatchdog() throws {
        let h = EngineHarness()
        try h.engine.start()
        h.capture.health = CaptureHealth(signalSeen: true, silentSeconds: 1)
        h.clock.advance(by: 1)
        #expect(h.capture.rebuildCount == 0)
        h.capture.health = CaptureHealth(signalSeen: true, silentSeconds: ShiftEngine.silentSecondsBeforeRebuild)
        h.clock.advance(by: 1)
        #expect(h.capture.rebuildCount == 1)
        // The rebuilt tap has seen no signal yet (music paused): no rebuild loop.
        h.clock.advance(by: 30)
        #expect(h.capture.rebuildCount == 1)
    }

    @Test("no signal at all since start shows a notice; a signal clears it")
    func noSignalNotice() throws {
        let h = EngineHarness()
        try h.engine.start()
        #expect(h.engine.notice == nil)
        h.clock.advance(by: ShiftEngine.noSignalNoticeAfter + 1)
        #expect(h.engine.notice != nil)
        h.capture.health = CaptureHealth(signalSeen: true, silentSeconds: 0)
        h.clock.advance(by: 1)
        #expect(h.engine.notice == nil)
    }

    @Test("a failed output start leaves nothing running and reports the error")
    func failedStart() {
        let h = EngineHarness()
        h.output.failStart = FakeError(description: "device busy")
        #expect(throws: (any Error).self) { try h.engine.start() }
        #expect(h.engine.state == .failed("device busy"))
        #expect(!h.capture.isRunning && h.capture.prepareCount == 0)
        // The router is stopped too: later hardware events do nothing.
        h.output.failStart = nil
        h.provider.setDefault(airPods.id)
        h.settle()
        #expect(h.output.starts.isEmpty)
    }

    @Test("a failed tap creation stops the output that was already started")
    func failedPrepare() {
        let h = EngineHarness()
        h.capture.failPrepare = FakeError(description: "no tap")
        #expect(throws: (any Error).self) { try h.engine.start() }
        #expect(!h.output.isRunning)
        #expect(h.engine.state == .failed("no tap"))
    }

    @Test("a failure during a rebind is reported, and the next rebind retries")
    func failedRebindRetries() throws {
        let h = EngineHarness()
        try h.engine.start()
        h.output.failStart = FakeError(description: "AirPods not ready")
        h.provider.setDefault(airPods.id)
        h.settle()
        #expect(h.engine.state == .failed("AirPods not ready"))
        #expect(!h.capture.isRunning, "nothing stays tapped (muted) while the output is down")
        h.output.failStart = nil
        h.provider.setDefault(speakers.id)
        h.settle()
        #expect(h.engine.state == .running(speakers.id))
    }

    @Test("stop tears down both sides, stops the router and the watchdog")
    func stopTearsDown() throws {
        let h = EngineHarness()
        try h.engine.start()
        h.engine.stop()
        #expect(h.engine.state == .off)
        #expect(!h.capture.isRunning && !h.output.isRunning)
        h.log.calls = []
        h.capture.health = CaptureHealth(signalSeen: true, silentSeconds: 100)
        h.provider.setDefault(airPods.id)
        h.clock.advance(by: 10)
        #expect(h.log.calls.isEmpty)
    }

    @Test("pitch changes reach the output while running and are used at the next start")
    func pitchChange() throws {
        let h = EngineHarness()
        h.engine.setPitchCents(PitchMode.demo.pitchCents)
        try h.engine.start()
        #expect(h.output.starts.last?.pitchCents == -100)
        h.engine.setPitchCents(0)
        #expect(h.output.pitch == 0)
    }
}
