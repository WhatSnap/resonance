import Accelerate
import Foundation

/// Finds the dominant frequency of a signal: Hann window, zero-padded real FFT, then
/// parabolic interpolation on the log magnitude around the strongest bin.
enum PeakFrequency {
    static func estimate(_ signal: [Float], sampleRate: Double) -> Double {
        // Use the largest power of two that fits, zero-padded 4x for a finer grid.
        let used = 1 << Int(log2(Double(signal.count)))
        let n = used * 4
        let log2n = vDSP_Length(log2(Double(n)))

        var window = [Float](repeating: 0, count: used)
        vDSP_hann_window(&window, vDSP_Length(used), Int32(vDSP_HANN_NORM))
        var padded = [Float](repeating: 0, count: n)
        vDSP_vmul(signal, 1, window, 1, &padded, 1, vDSP_Length(used))

        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return .nan }
        defer { vDSP_destroy_fftsetup(setup) }

        let half = n / 2
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                padded.withUnsafeBufferPointer { pp in
                    pp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }
        magnitudes[0] = 0 // packed DC/Nyquist slot

        var peakValue: Float = 0
        var peakIndex: vDSP_Length = 0
        vDSP_maxvi(magnitudes, 1, &peakValue, &peakIndex, vDSP_Length(half))
        let k = Int(peakIndex)
        guard k > 0, k < half - 1 else { return Double(k) * sampleRate / Double(n) }

        let a = log(Double(magnitudes[k - 1]) + 1e-20)
        let b = log(Double(magnitudes[k]) + 1e-20)
        let c = log(Double(magnitudes[k + 1]) + 1e-20)
        let offset = 0.5 * (a - c) / (a - 2 * b + c)
        return (Double(k) + offset) * sampleRate / Double(n)
    }
}
