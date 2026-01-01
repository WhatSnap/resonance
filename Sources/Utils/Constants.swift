import Foundation

enum Constants {
    static let appName = "Resonance"
    static let bundleIdentifier = "com.resonance.app"
    static let version = "1.0.0"
    
    enum Audio {
        static let sourceFrequency: Float = 440.0
        static let targetFrequency: Float = 432.0
        static let pitchRatio: Float = targetFrequency / sourceFrequency
        static let centsShift: Float = -31.77
        
        static let fftSize = 4096
        static let hopSize = 1024
    }
}
