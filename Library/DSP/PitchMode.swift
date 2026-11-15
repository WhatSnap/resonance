import Foundation

/// A tuning the app can apply. Moved from `AudioEngine` (HQ-430) so the DSP baseline tests can read it.
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

    /// Cents to apply relative to 440Hz tuning.
    public var pitchCents: Float {
        switch self {
        case .off: return 0
        case .hz174: return -1607.82
        case .hz285: return -752.09
        case .hz396: return -182.40
        case .hz417: return -93.13
        case .hz432: return -31.77
        case .hz444: return 15.67
        case .hz528: return 315.64
        case .hz639: return 647.21
        case .hz741: return 902.49
        case .hz852: return 1144.87
        case .hz963: return 1356.38
        case .demo: return -100
        }
    }

    /// Where a 440 Hz tone lands after the shift: `440 · 2^(cents/1200)`.
    public var targetFrequency: Double {
        Self.referenceFrequency * pow(2, Double(pitchCents) / 1200)
    }
}
