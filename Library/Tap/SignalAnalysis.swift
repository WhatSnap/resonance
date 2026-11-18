import Accelerate
import Foundation

/// Measurements on captured audio: level, dominant frequency and the level of one tone.
public enum SignalAnalysis {
    /// Root mean square of the samples; 0 for an empty array.
    public static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        return vDSP.rootMeanSquare(samples)
    }

    /// Largest absolute sample value; 0 for an empty buffer.
    public static func peak(_ samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        return vDSP.maximumMagnitude(samples)
    }

    /// One channel out of interleaved samples.
    public static func channel(_ index: Int, of interleaved: [Float], channels: Int) -> [Float] {
        precondition(channels > 0 && index < channels)
        return stride(from: index, to: interleaved.count, by: channels).map { interleaved[$0] }
    }

    /// The dominant frequency in Hz: Hann-windowed FFT, then Gaussian interpolation around the peak bin.
    /// Returns nil when the signal is silent.
    public static func peakFrequency(_ samples: [Float], sampleRate: Double) -> Double? {
        guard samples.count >= 64 else { return nil }
        let log2n = vDSP_Length(Int(log2(Double(samples.count)).rounded(.down)))
        let n = 1 << Int(log2n)
        // Take the most recent power-of-two block; no zero padding keeps the bins exact.
        var block = Array(samples.suffix(n))
        let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: n, isHalfWindow: false)
        vDSP.multiply(block, window, result: &block)

        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetup(setup) }

        let half = n / 2
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var power = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                block.withUnsafeBytes { raw in
                    vDSP_ctoz(raw.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(half))
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                split.imagp[0] = 0 // packed Nyquist term; ignore it
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(half))
            }
        }
        power[0] = 0 // DC
        guard let maxIndex = power.indices.max(by: { power[$0] < power[$1] }), power[maxIndex] > 1e-12 else {
            return nil
        }
        var offset = 0.0
        if maxIndex > 0, maxIndex < half - 1 {
            let a = log(Double(max(power[maxIndex - 1], 1e-30)))
            let b = log(Double(power[maxIndex]))
            let c = log(Double(max(power[maxIndex + 1], 1e-30)))
            let denominator = a - 2 * b + c
            if denominator != 0 { offset = 0.5 * (a - c) / denominator }
        }
        return (Double(maxIndex) + offset) * sampleRate / Double(n)
    }

    /// Amplitude of the component at `frequency` (a single-bin DFT, scaled so a sine of amplitude A gives about A).
    public static func magnitude(at frequency: Double, in samples: [Float], sampleRate: Double) -> Double {
        guard !samples.isEmpty else { return 0 }
        let omega = 2 * Double.pi * frequency / sampleRate
        var re = 0.0
        var im = 0.0
        for (index, sample) in samples.enumerated() {
            let phase = omega * Double(index)
            re += Double(sample) * cos(phase)
            im -= Double(sample) * sin(phase)
        }
        return 2 * (re * re + im * im).squareRoot() / Double(samples.count)
    }
}

/// Decides when a tap has gone silent for long enough that it must be torn down and rebuilt.
/// A known failure: a tap can keep delivering all-zero buffers, and only destroying both the tap and its
/// aggregate device recovers it.
public struct SilenceWatchdog: Sendable {
    public let silentBuffersBeforeRebuild: Int
    public let armOnFirstSignal: Bool
    private var silentRun = 0
    private var armed: Bool

    public init(silentBuffersBeforeRebuild: Int, armOnFirstSignal: Bool = false) {
        precondition(silentBuffersBeforeRebuild > 0)
        self.silentBuffersBeforeRebuild = silentBuffersBeforeRebuild
        self.armOnFirstSignal = armOnFirstSignal
        self.armed = !armOnFirstSignal
    }

    /// Feed the peak of one buffer. Returns true once, when the silent run reaches the threshold.
    public mutating func observe(peak: Float) -> Bool {
        if peak > 0 {
            armed = true
            silentRun = 0
            return false
        }
        guard armed else { return false }
        silentRun += 1
        if silentRun == silentBuffersBeforeRebuild { return true }
        return false
    }

    public mutating func reset() {
        silentRun = 0
        armed = !armOnFirstSignal
    }
}
