import CoreAudio
import Foundation
import Testing
@testable import ResonanceCore

/// The whole engine on real hardware: a process tap on a child that plays 440 Hz to BlackHole, the buffer,
/// NewTimePitch, and the HAL output on BlackHole. Reading BlackHole back must give 432 Hz.
///
/// Silence: the child plays only to BlackHole; the tap lists only the child (never global); the router reads a fake
/// provider whose only device is BlackHole, so the real default output is never followed and never written. Off
/// unless `RESONANCE_TAP_SPIKE=1`, because a tap needs the System Audio Recording permission.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["RESONANCE_TAP_SPIKE"] == "1" && SilentSink.available),
       .serialized)
struct TapEngineIntegrationTests {
    @Test("tap a child at 440 Hz, render to BlackHole, read back a 432 Hz peak; default output untouched")
    func tapToBlackHoleGives432() async throws {
        guard #available(macOS 14.4, *) else { return }
        let defaultBefore = try CoreAudioObjects.defaultOutputDevice()
        let sink = try SilentSink.device()
        let rate = try CoreAudioObjects.nominalSampleRate(of: sink)

        let child = try SpikeSupport.launchSineChild(deviceUID: SilentSink.uid, frequency: 440, seconds: 60)
        defer { child.terminate(); child.waitUntilExit() }
        let processLookup = try await SpikeSupport.waitForProcessObject(pid: child.processIdentifier)
        let process = try #require(processLookup, "child never registered with Core Audio")

        let monitor = try LoopbackMonitor(device: sink)
        defer { monitor.stop() }

        let provider = FakeDeviceProvider()
        provider.deviceList = [.init(id: sink, name: "BlackHole 2ch", sampleRate: rate)]
        provider.defaultOutput = sink
        let clock = FakeScheduler()
        let router = DeviceRouter(provider: provider, scheduler: clock)
        let capture = TapCapture(target: .processes([process]))
        #expect(!capture.isGlobal, "the test taps the child only")
        let output = HALOutput()
        let engine = ShiftEngine(capture: capture, output: output, router: router, scheduler: clock)
        engine.setPitchCents(PitchMode.hz432.pitchCents)
        try engine.start()
        defer { engine.stop() }
        #expect(engine.state == .running(sink))

        try await Task.sleep(for: .milliseconds(2000))
        let tail = monitor.tail(seconds: 1, rate: rate)
        let hz = SignalAnalysis.peakFrequency(tail, sampleRate: rate)
        let at432 = SignalAnalysis.magnitude(at: PitchMode.hz432.targetFrequency, in: tail, sampleRate: rate)
        let at440 = SignalAnalysis.magnitude(at: 440, in: tail, sampleRate: rate)
        let health = capture.currentHealth()
        print("TAP-ENGINE", "peak", hz ?? 0, "at432", at432, "at440", at440, "health", health)

        let peak = try #require(hz, "something reached BlackHole")
        #expect(abs(peak - PitchMode.hz432.targetFrequency) <= 1, "peak \(peak) Hz")
        #expect(at440 < at432 * 0.1, "the original 440 Hz is muted by the tap")
        #expect(health.signalSeen)

        engine.stop()
        #expect(try CoreAudioObjects.defaultOutputDevice() == defaultBefore, "default output unchanged")
    }
}

@MainActor
@Suite("TapCapture guard")
struct TapCaptureGuardTests {
    @Test("a global tap is refused inside the test process, before anything is created")
    func globalTapRefusedInTests() throws {
        guard #available(macOS 14.4, *) else { return }
        let capture = TapCapture(target: .systemExcludingSelf)
        #expect(capture.isGlobal)
        #expect(throws: TapCaptureError.globalTapRefusedInTests) { _ = try capture.prepare() }
        #expect(capture.currentSampleRate() == nil)
    }
}
