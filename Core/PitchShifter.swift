import Foundation
import Accelerate

class PitchShifter {
    private let fftSize: Int = 4096
    private let hopSize: Int = 1024
    private let pitchRatio: Float = 432.0 / 440.0
    
    private let fftProcessor: FFTProcessor
    
    private var inputAccumulator: [Float] = []
    private var outputAccumulator: [Float]
    
    private var lastInputPhases: [Float]
    private var lastOutputPhases: [Float]
    
    init() {
        self.fftProcessor = FFTProcessor(fftSize: fftSize)
        self.outputAccumulator = [Float](repeating: 0, count: fftSize * 2)
        self.lastInputPhases = [Float](repeating: 0, count: fftSize / 2)
        self.lastOutputPhases = [Float](repeating: 0, count: fftSize / 2)
    }
    
    func process(input: [Float]) -> [Float] {
        inputAccumulator.append(contentsOf: input)
        
        var output: [Float] = []
        
        while inputAccumulator.count >= fftSize {
            let window = Array(inputAccumulator.prefix(fftSize))
            inputAccumulator.removeFirst(hopSize)
            
            let processedFrame = shiftFrame(window)
            
            // Overlap-add
            for i in 0..<fftSize {
                outputAccumulator[i] += processedFrame[i]
            }
            
            // Extract output
            output.append(contentsOf: outputAccumulator.prefix(hopSize))
            outputAccumulator.removeFirst(hopSize)
            outputAccumulator.append(contentsOf: [Float](repeating: 0, count: hopSize))
        }
        
        return output.count == input.count ? output : Array(output.prefix(input.count))
    }
    
    private func shiftFrame(_ frame: [Float]) -> [Float] {
        let (magnitudes, phases) = fftProcessor.forward(buffer: frame)
        
        var newMagnitudes = [Float](repeating: 0, count: fftSize / 2)
        var newPhases = [Float](repeating: 0, count: fftSize / 2)
        
        for i in 0..<fftSize / 2 {
            let bin = Float(i) * pitchRatio
            let intBin = Int(bin)
            let fracBin = bin - Float(intBin)
            
            if intBin < fftSize / 2 - 1 {
                // Linear interpolation for magnitude
                newMagnitudes[intBin] += magnitudes[i] * (1.0 - fracBin)
                newMagnitudes[intBin + 1] += magnitudes[i] * fracBin
                
                // Phase accumulation
                let phaseDiff = phases[i] - lastInputPhases[i]
                lastInputPhases[i] = phases[i]
                
                let expectedPhaseDiff = 2.0 * .pi * Float(i) * Float(hopSize) / Float(fftSize)
                var deltaPhase = phaseDiff - expectedPhaseDiff
                
                // Wrap deltaPhase to [-pi, pi]
                while deltaPhase > .pi { deltaPhase -= 2.0 * .pi }
                while deltaPhase < -.pi { deltaPhase += 2.0 * .pi }
                
                let scaledDeltaPhase = deltaPhase * pitchRatio
                let newPhase = lastOutputPhases[i] + expectedPhaseDiff + scaledDeltaPhase
                newPhases[i] = newPhase
                lastOutputPhases[i] = newPhase
            }
        }
        
        return fftProcessor.inverse(magnitudes: newMagnitudes, phases: newPhases)
    }
}
