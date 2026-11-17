import Testing
@testable import ResonanceCore

@MainActor
@Suite("EngineViewModel")
struct EngineViewModelTests {
    final class Count { var value = 0 }

    @Test("a failed start shows its message in the menu and the switch stays off")
    func failedStartShowsMessage() {
        let h = EngineHarness()
        h.output.failStart = FakeError(description: "The output device could not start.")
        let model = EngineViewModel(engine: h.engine)
        model.setEnabled(true)
        #expect(model.isEnabled == false)
        #expect(model.errorMessage == "The output device could not start.")
        #expect(model.statusText == "Stopped")
    }

    @Test("turning on clears an old error and shows the running state")
    func successfulStartClearsError() {
        let h = EngineHarness()
        h.output.failStart = FakeError(description: "busy")
        let model = EngineViewModel(engine: h.engine)
        model.setEnabled(true)
        h.output.failStart = nil
        model.setEnabled(true)
        #expect(model.isEnabled)
        #expect(model.errorMessage == nil)
        #expect(model.statusText == "On")
    }

    @Test("an error after start (during a device change) shows in the menu; the switch stays on and the status agrees")
    func runtimeErrorShows() {
        let h = EngineHarness()
        let model = EngineViewModel(engine: h.engine)
        model.setEnabled(true)
        h.output.failStart = FakeError(description: "AirPods not ready")
        h.provider.setDefault(airPods.id)
        h.settle()
        #expect(model.isEnabled)
        #expect(model.errorMessage == "AirPods not ready")
        #expect(model.statusText == EngineViewModel.interruptedStatus)
        // The engine retries at the next device change and the status follows.
        h.output.failStart = nil
        h.provider.setDefault(speakers.id)
        h.settle()
        #expect(model.isEnabled && model.statusText == "On")
    }

    @Test("headset profile stays On; no output shows as waiting")
    func headsetOnAndWaiting() {
        let h = EngineHarness()
        let model = EngineViewModel(engine: h.engine)
        model.setEnabled(true)
        h.provider.setRate(speakers.id, 16_000)
        h.settle()
        #expect(model.statusText == "On")
        h.provider.setRate(speakers.id, 48_000)
        h.provider.disconnect(speakers.id)
        h.provider.setDefault(nil)
        h.settle()
        #expect(model.statusText == "Waiting for an output device")
    }

    @Test("the pitch mode reaches the engine")
    func pitchMode() {
        let h = EngineHarness()
        let model = EngineViewModel(engine: h.engine)
        model.setEnabled(true)
        model.pitchMode = .demo
        #expect(h.output.pitch == PitchMode.demo.pitchCents)
    }

    @Test("turning off stops the engine; shutdown stops it and runs the cleanup once")
    func offAndShutdown() {
        let h = EngineHarness()
        let cleanups = Count()
        let model = EngineViewModel(engine: h.engine, onShutdown: { cleanups.value += 1 })
        model.setEnabled(true)
        model.setEnabled(false)
        #expect(h.engine.state == .off)
        #expect(!model.isEnabled && model.statusText == "Off")
        model.setEnabled(true)
        model.shutdown()
        model.shutdown()
        #expect(h.engine.state == .off)
        #expect(cleanups.value == 1)
    }
}
