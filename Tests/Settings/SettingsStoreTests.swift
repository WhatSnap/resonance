import Foundation
import Testing
@testable import ResonanceCore

/// A fresh, isolated defaults suite per test. Never touches `.standard`.
private func isolatedDefaults() -> UserDefaults {
    let name = "resonance.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@Suite("SettingsStore")
struct SettingsStoreTests {
    @Test("A fresh install starts disabled at 432 Hz")
    func freshDefaults() {
        let store = SettingsStore(defaults: isolatedDefaults())
        #expect(store.isEnabled == false)
        #expect(store.pitchMode == .hz432)
    }

    @Test("Enabled state and pitch mode survive a relaunch")
    func survivesRelaunch() {
        let defaults = isolatedDefaults()
        let first = SettingsStore(defaults: defaults)
        first.isEnabled = true
        first.pitchMode = .hz528

        // A relaunch is a new store over the same suite.
        let second = SettingsStore(defaults: defaults)
        #expect(second.isEnabled == true)
        #expect(second.pitchMode == .hz528)
    }

    @Test("Turning it off again also persists")
    func disablePersists() {
        let defaults = isolatedDefaults()
        let first = SettingsStore(defaults: defaults)
        first.isEnabled = true
        first.isEnabled = false
        #expect(SettingsStore(defaults: defaults).isEnabled == false)
    }

    @Test("An unknown stored pitch mode falls back to 432 Hz")
    func unknownPitchModeFallsBack() {
        let defaults = isolatedDefaults()
        defaults.set("hz9999", forKey: SettingsStore.Key.pitchMode)
        #expect(SettingsStore(defaults: defaults).pitchMode == .hz432)
    }

    @Test("Every pitch mode round-trips")
    func everyModeRoundTrips() {
        let defaults = isolatedDefaults()
        for mode in PitchMode.allCases {
            SettingsStore(defaults: defaults).pitchMode = mode
            #expect(SettingsStore(defaults: defaults).pitchMode == mode)
        }
    }
}
