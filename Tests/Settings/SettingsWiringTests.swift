import Foundation
import Testing
@testable import ResonanceCore

/// The settings wired into the menu view model (HQ-434, wiring part). Every test uses its own suite, never `.standard`.
@MainActor
@Suite("Settings wiring")
struct SettingsWiringTests {
    static func isolatedStore() -> SettingsStore {
        let name = "resonance.tests.wiring.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return SettingsStore(defaults: defaults)
    }

    @Test("saved enabled and mode: the app starts enabled in that mode, and the saved state is kept")
    func savedEnabledStarts() {
        let store = Self.isolatedStore()
        store.isEnabled = true
        store.pitchMode = .demo
        let h = EngineHarness()
        let model = EngineViewModel(engine: h.engine, settings: store)
        model.restore()
        #expect(model.isEnabled)
        #expect(model.statusText == "On")
        #expect(model.pitchMode == .demo)
        #expect(h.output.pitch == PitchMode.demo.pitchCents)
        #expect(store.isEnabled)
        #expect(store.pitchMode == .demo)
    }

    @Test("fresh install: restore leaves the app off and saves nothing")
    func freshInstallStaysOff() {
        let store = Self.isolatedStore()
        let h = EngineHarness()
        let model = EngineViewModel(engine: h.engine, settings: store)
        model.restore()
        #expect(!model.isEnabled)
        #expect(h.engine.state == .off)
        #expect(store.isEnabled == false)
        #expect(store.pitchMode == .hz432)
    }

    @Test("the user's switch and tuning are saved")
    func userChoicesPersist() {
        let store = Self.isolatedStore()
        let h = EngineHarness()
        let model = EngineViewModel(engine: h.engine, settings: store)
        model.restore()
        model.setEnabled(true)
        model.pitchMode = .demo
        #expect(store.isEnabled)
        #expect(store.pitchMode == .demo)
        model.setEnabled(false)
        #expect(store.isEnabled == false)
    }

    @Test("a headset pause does not save off")
    func headsetPauseDoesNotSaveOff() {
        let store = Self.isolatedStore()
        let h = EngineHarness()
        let model = EngineViewModel(engine: h.engine, settings: store)
        model.restore()
        model.setEnabled(true)
        h.provider.setRate(speakers.id, 16_000)
        h.settle()
        #expect(model.statusText == "Paused while the headset is in call mode")
        #expect(store.isEnabled)
    }

    @Test("quitting does not save off")
    func shutdownDoesNotSaveOff() {
        let store = Self.isolatedStore()
        let h = EngineHarness()
        let model = EngineViewModel(engine: h.engine, settings: store)
        model.restore()
        model.setEnabled(true)
        model.shutdown()
        #expect(store.isEnabled)
    }

    @Test("a failed restore shows the error, and the saved state stays on for the next action to decide")
    func failedRestoreShowsError() {
        let store = Self.isolatedStore()
        store.isEnabled = true
        let h = EngineHarness()
        h.output.failStart = FakeError(description: "The output device could not start.")
        let model = EngineViewModel(engine: h.engine, settings: store)
        model.restore()
        #expect(!model.isEnabled)
        #expect(model.errorMessage == "The output device could not start.")
        #expect(store.isEnabled)
    }
}

@MainActor
@Suite("OpenAtLoginModel")
struct OpenAtLoginModelTests {
    @Test("off on a fresh install")
    func offByDefault() {
        let item = FakeLoginItem()
        let model = OpenAtLoginModel(toggle: OpenAtLogin(item: item))
        #expect(model.isOn == false)
        #expect(item.registerCalls == 0)
    }

    @Test("the switch registers and unregisters")
    func switchRegisters() {
        let item = FakeLoginItem()
        let model = OpenAtLoginModel(toggle: OpenAtLogin(item: item))
        model.set(true)
        #expect(model.isOn && item.isRegistered)
        model.set(false)
        #expect(!model.isOn && !item.isRegistered)
    }

    @Test("a failure puts the switch back and says why")
    func failureShows() {
        let item = FakeLoginItem()
        item.failNext = FakeError(description: "Not allowed")
        let model = OpenAtLoginModel(toggle: OpenAtLogin(item: item))
        model.set(true)
        #expect(model.isOn == false)
        #expect(model.errorMessage == "Not allowed")
        model.set(true)
        #expect(model.isOn)
        #expect(model.errorMessage == nil)
    }

    @Test("refresh picks up a removal made in System Settings")
    func refreshReadsSystem() {
        let item = FakeLoginItem()
        let model = OpenAtLoginModel(toggle: OpenAtLogin(item: item))
        model.set(true)
        item.isRegistered = false
        model.refresh()
        #expect(model.isOn == false)
    }
}
