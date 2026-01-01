import Foundation
import Accelerate

class FFTProcessor {
    private let fftSize: Int
    private let log2FFTSize: Int
    private let fftSetup: FFTSetup
    
    private var real: [Float]
    private var imag: [Float]
    private var splitComplex: DSPSplitComplex
    
    init(fftSize: Int) {
        self.fftSize = fftSize
        self.log2FFTSize = Int(log2(Double(fftSize)))
        self.fftSetup = vDSP_create_fftsetup(vDSP_Length(log2FFTSize), FFTRadix(kFFTRadix2))!
        
        self.real = [Float](repeating: 0, count: fftSize / 2)
        self.imag = [Float](repeating: 0, count: fftSize / 2)
        self.splitComplex = DSPSplitComplex(realp: &self.real, imagp: &self.imag)
    }
    
    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }
    
    func forward(buffer: [Float]) -> (magnitudes: [Float], phases: [Float]) {
        var buffer = buffer
        // Windowing (Hanning)
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(buffer, 1, window, 1, &buffer, 1, vDSP_Length(fftSize))
        
        // FFT
        buffer.withUnsafeBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexPtr in
                vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(fftSize / 2))
            }
        }
        
        vDSP_fft_zrip(fftSetup, &splitComplex, 1, vDSP_Length(log2FFTSize), FFTDirection(kFFTDirection_Forward))
        
        // Scale
        var scale = Float(1.0 / 2.0)
        vDSP_vsmul(splitComplex.realp, 1, &scale, splitComplex.realp, 1, vDSP_Length(fftSize / 2))
        vDSP_vsmul(splitComplex.imagp, 1, &scale, splitComplex.imagp, 1, vDSP_Length(fftSize / 2))
        
        // Calculate magnitudes and phases
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        var phases = [Float](repeating: 0, count: fftSize / 2)
        
        vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
        vDSP_zvphas(&splitComplex, 1, &phases, 1, vDSP_Length(fftSize / 2))
        
        return (magnitudes, phases)
    }
    
    func inverse(magnitudes: [Float], phases: [Float]) -> [Float] {
        var magnitudes = magnitudes
        var phases = phases
        
        // Reconstruct complex data
        vDSP_zvrect(&magnitudes, 1, &phases, 1, &splitComplex, 1, vDSP_Length(fftSize / 2))
        
        // IFFT
        vDSP_fft_zrip(fftSetup, &splitComplex, 1, vDSP_Length(log2FFTSize), FFTDirection(kFFTDirection_Inverse))
        
        // Scale IFFT result
        var scale = Float(1.0 / Float(fftSize))
        vDSP_vsmul(splitComplex.realp, 1, &scale, splitComplex.realp, 1, vDSP_Length(fftSize / 2))
        vDSP_vsmul(splitComplex.imagp, 1, &scale, splitComplex.imagp, 1, vDSP_Length(fftSize / 2))
        
        var output = [Float](repeating: 0, count: fftSize)
        output.withUnsafeMutableBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexPtr in
                vDSP_ztoc(&splitComplex, 1, complexPtr, 2, vDSP_Length(fftSize / 2))
            }
        }
        
        return output
    }
}
