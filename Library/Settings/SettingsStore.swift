import Foundation

/// What Resonance remembers across relaunches (HQ-434): whether it is on, and which tuning.
///
/// Every read goes to `UserDefaults`, so a new store over the same suite sees what the last one wrote.
/// The app passes `.standard`; tests pass an isolated suite.
public final class SettingsStore {
    public enum Key {
        public static let isEnabled = "resonance.isEnabled"
        public static let pitchMode = "resonance.pitchMode"
    }

    /// Fresh-install values. They match the app's behavior before HQ-434.
    public static let defaultIsEnabled = false
    public static let defaultPitchMode: PitchMode = .hz432

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isEnabled: Bool {
        get { defaults.object(forKey: Key.isEnabled) as? Bool ?? Self.defaultIsEnabled }
        set { defaults.set(newValue, forKey: Key.isEnabled) }
    }

    /// An unknown stored value (a mode removed in a later version) falls back to the default.
    public var pitchMode: PitchMode {
        get { defaults.string(forKey: Key.pitchMode).flatMap(PitchMode.init(rawValue:)) ?? Self.defaultPitchMode }
        set { defaults.set(newValue.rawValue, forKey: Key.pitchMode) }
    }
}
