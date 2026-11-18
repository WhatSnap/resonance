import Foundation

/// A tuning the app can apply. Moved out of the 1.0 engine (HQ-430) so the DSP baseline tests can read it.
public enum PitchMode: String, CaseIterable, Identifiable, Sendable {
    case off
    case hz174
    case hz285
    case hz396
    case hz417
    case hz432
    case hz444
    case hz528
    case hz639
    case hz741
    case hz852
    case hz963
    case demo

    /// Reference tuning the shift is relative to.
    public static let referenceFrequency: Double = 440

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off: return "Off (440Hz)"
        case .hz174: return "174Hz - Security & Comfort"
        case .hz285: return "285Hz - Cellular Repair"
        case .hz396: return "396Hz - Liberation from Fear"
        case .hz417: return "417Hz - Facilitating Change"
        case .hz432: return "432Hz - Natural Tuning"
        case .hz444: return "444Hz - Love (528C)"
        case .hz528: return "528Hz - DNA Repair"
        case .hz639: return "639Hz - Relationships"
        case .hz741: return "741Hz - Expression"
        case .hz852: return "852Hz - Intuition"
        case .hz963: return "963Hz - Divine Connection"
        case .demo: return "Demo (-1 Semitone)"
        }
    }

    /// The frequency a 440 Hz tone should land on, by name. `nil` for the demo, which is a plain semitone.
    public var nominalTarget: Double? {
        switch self {
        case .off: return 440
        case .hz174: return 174
        case .hz285: return 285
        case .hz396: return 396
        case .hz417: return 417
        case .hz432: return 432
        case .hz444: return 444
        case .hz528: return 528
        case .hz639: return 639
        case .hz741: return 741
        case .hz852: return 852
        case .hz963: return 963
        case .demo: return nil
        }
    }

    /// Cents to apply relative to 440Hz tuning: exactly `1200 · log2(target / 440)` (HQ-435).
    public var pitchCents: Float {
        guard let target = nominalTarget else { return -100 }
        return Float(1200 * log2(target / Self.referenceFrequency))
    }

    /// Where a 440 Hz tone lands after the shift: `440 · 2^(cents/1200)`.
    public var targetFrequency: Double {
        Self.referenceFrequency * pow(2, Double(pitchCents) / 1200)
    }
}
