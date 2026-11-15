import CoreAudio
import Foundation
import Testing
@testable import ResonanceCore

/// The real output (AUHAL + NewTimePitch) on BlackHole 2ch. No tap, so no capture permission is involved.
/// Silent: BlackHole loops to its own input only. Skipped when BlackHole is missing or the old app is running.
@MainActor
@Suite(.enabled(if: SilentSink.available), .serialized)
struct SilentSinkTests {
    static let target = PitchMode.hz432.targetFrequency

    @Test("HAL output shifts a 440 Hz feed to a 432 Hz peak on BlackHole")
    func outputShiftsTo432() async throws {
        let defaultBefore = try CoreAudioObjects.defaultOutputDevice()
        let sink = try SilentSink.device()
        let rate = try CoreAudioObjects.nominalSampleRate(of: sink)
        let monitor = try LoopbackMonitor(device: sink)
        defer { monitor.stop() }

        let buffer = DriftCompensatedBuffer(config: DriftBufferConfig(sampleRate: rate))
        let source = SineCapture(frequency: 440, rate: rate)
        let output = HALOutput()
        try output.start(deviceID: sink, clientSampleRate: rate, buffer: buffer, pitchCents: PitchMode.hz432.pitchCents)
        try source.start(into: buffer)
        try await Task.sleep(for: .milliseconds(1500))
        let peak = SignalAnalysis.peakFrequency(monitor.tail(seconds: 1, rate: rate), sampleRate: rate)
        source.stop()
        output.stop()

        let hz = try #require(peak, "something reached BlackHole")
        #expect(abs(hz - Self.target) <= 1, "peak \(hz) Hz, want \(Self.target) Hz")
        #expect(output.renderCount > 0)
        #expect(try CoreAudioObjects.defaultOutputDevice() == defaultBefore, "default output unchanged")
    }

    @Test("a rebind from the router restarts only the output, within 200 ms")
    func rebindWithin200ms() async throws {
        let defaultBefore = try CoreAudioObjects.defaultOutputDevice()
        let sink = try SilentSink.device()
        let rate = try CoreAudioObjects.nominalSampleRate(of: sink)
        let monitor = try LoopbackMonitor(device: sink)
        defer { monitor.stop() }

        // Fake provider whose only device is the real BlackHole.
        let provider = FakeDeviceProvider()
        provider.deviceList = [.init(id: sink, name: "BlackHole 2ch", sampleRate: rate)]
        provider.defaultOutput = sink
        let clock = FakeScheduler()
        let router = DeviceRouter(provider: provider, scheduler: clock)
        let capture = SineCapture(frequency: 440, rate: rate)
        let output = HALOutput()
        let engine = ShiftEngine(capture: capture, output: output, router: router, scheduler: clock)
        engine.setPitchCents(PitchMode.hz432.pitchCents)
        try engine.start()
        defer { engine.stop() }
        try await Task.sleep(for: .milliseconds(500))
        let rendersBefore = output.renderCount
        let startsBefore = output.startCount
        #expect(rendersBefore > 0)

        // The router sees a rate change on the default output: one rebind.
        let t0 = HostClock.now()
        provider.setRate(sink, rate == 48_000 ? 44_100 : 48_000)
        clock.advance(by: DeviceRouter.defaultDebounce)
        var firstRender: Double?
        while HostClock.now() - t0 < 1 {
            if output.startCount > startsBefore, output.renderCountSinceStart > 0 { firstRender = HostClock.now(); break }
            try await Task.sleep(for: .milliseconds(1))
        }
        let elapsed = try #require(firstRender, "the output rendered again after the rebind") - t0
        print("REBIND-ELAPSED-MS", (elapsed * 1000).rounded())
        #expect(elapsed <= 0.2, "rebind to first render took \(elapsed * 1000) ms")
        #expect(output.startCount == startsBefore + 1, "the output restarted once")
        #expect(capture.startCount == 1 && capture.prepareCount == 1, "capture was not restarted")
        #expect(engine.state == .running(sink))

        // And the shifted tone keeps playing after the rebind.
        try await Task.sleep(for: .milliseconds(1200))
        let hz = SignalAnalysis.peakFrequency(monitor.tail(seconds: 1, rate: rate), sampleRate: rate)
        #expect(hz.map { abs($0 - Self.target) <= 1 } == true, "peak after rebind: \(String(describing: hz))")
        #expect(try CoreAudioObjects.defaultOutputDevice() == defaultBefore, "default output unchanged")
    }
}

extension LoopbackMonitor {
    /// The last `seconds` of loopback audio.
    func tail(seconds: Double, rate: Double) -> [Float] {
        let n = Int(seconds * rate)
        return samples(from: mark() - n, count: n)
    }
}
