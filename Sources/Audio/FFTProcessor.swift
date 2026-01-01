import Foundation
import Accelerate

// Used from the realtime audio thread via PitchShifter.
final class FFTProcessor: @unchecked Sendable {
    private let fftSize: Int
    private let log2FFTSize: Int
    private let fftSetup: FFTSetup
    
    private var realp: UnsafeMutablePointer<Float>
    private var imagp: UnsafeMutablePointer<Float>
    private var splitComplex: DSPSplitComplex
    
    init() {
        self.fftSize = Constants.Audio.fftSize
        self.log2FFTSize = Int(log2(Double(fftSize)))
        self.fftSetup = vDSP_create_fftsetup(vDSP_Length(log2FFTSize), FFTRadix(kFFTRadix2))!
        
        let halfSize = fftSize / 2
        self.realp = UnsafeMutablePointer<Float>.allocate(capacity: halfSize)
        self.imagp = UnsafeMutablePointer<Float>.allocate(capacity: halfSize)
        self.splitComplex = DSPSplitComplex(realp: realp, imagp: imagp)
    }
    
    deinit {
        vDSP_destroy_fftsetup(fftSetup)
        realp.deallocate()
        imagp.deallocate()
    }
    
    func forward(buffer: [Float]) -> (magnitudes: [Float], phases: [Float]) {
        var buffer = buffer
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(buffer, 1, window, 1, &buffer, 1, vDSP_Length(fftSize))
        
        buffer.withUnsafeBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexPtr in
                vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(fftSize / 2))
            }
        }
        
        vDSP_fft_zrip(fftSetup, &splitComplex, 1, vDSP_Length(log2FFTSize), FFTDirection(kFFTDirection_Forward))
        
        var scale = Float(0.5)
        vDSP_vsmul(splitComplex.realp, 1, &scale, splitComplex.realp, 1, vDSP_Length(fftSize / 2))
        vDSP_vsmul(splitComplex.imagp, 1, &scale, splitComplex.imagp, 1, vDSP_Length(fftSize / 2))
        
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        var phases = [Float](repeating: 0, count: fftSize / 2)
        
        vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
        vDSP_zvphas(&splitComplex, 1, &phases, 1, vDSP_Length(fftSize / 2))
        
        return (magnitudes, phases)
    }
    
    func inverse(magnitudes: [Float], phases: [Float]) -> [Float] {
        let halfSize = vDSP_Length(fftSize / 2)
        let count = Int(halfSize)
        
        // Use vForce for vector trigonometric operations
        var cosComponents = [Float](repeating: 0, count: count)
        var sinComponents = [Float](repeating: 0, count: count)
        
        var n = Int32(count)
        vvcosf(&cosComponents, phases, &n)
        vvsinf(&sinComponents, phases, &n)
        
        vDSP_vmul(magnitudes, 1, cosComponents, 1, realp, 1, halfSize)
        vDSP_vmul(magnitudes, 1, sinComponents, 1, imagp, 1, halfSize)
        
        vDSP_fft_zrip(fftSetup, &splitComplex, 1, vDSP_Length(log2FFTSize), FFTDirection(kFFTDirection_Inverse))
        
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
