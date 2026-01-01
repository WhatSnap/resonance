import Foundation
import Accelerate

// Used from AVAudioEngine tap callbacks (realtime audio queue).
// This type is not thread-safe for concurrent use, but it is used by a single audio thread,
// so we mark it as @unchecked Sendable to allow capture in @Sendable closures.
final class PitchShifter: @unchecked Sendable {
    private let fftSize: Int
    private let hopSize: Int
    private let pitchRatio: Float
    
    private let fftProcessor: FFTProcessor
    
    private var inputAccumulator: [Float] = []
    private var outputAccumulator: [Float]
    
    private var lastInputPhases: [Float]
    private var lastOutputPhases: [Float]
    
    init() {
        self.fftSize = Constants.Audio.fftSize
        self.hopSize = Constants.Audio.hopSize
        self.pitchRatio = Constants.Audio.pitchRatio
        
        self.fftProcessor = FFTProcessor()
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
            
            for i in 0..<fftSize {
                outputAccumulator[i] += processedFrame[i]
            }
            
            output.append(contentsOf: outputAccumulator.prefix(hopSize))
            outputAccumulator.removeFirst(hopSize)
            outputAccumulator.append(contentsOf: [Float](repeating: 0, count: hopSize))
        }
        
        // Ensure we return exactly the number of samples we received. During startup/buffering,
        // the algorithm may produce fewer samples than requested; pad to prevent downstream
        // out-of-range accesses in realtime callbacks.
        let trimmed = Array(output.prefix(input.count))
        if trimmed.count < input.count {
            return trimmed + [Float](repeating: 0, count: input.count - trimmed.count)
        }
        return trimmed
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
                newMagnitudes[intBin] += magnitudes[i] * (1.0 - fracBin)
                newMagnitudes[intBin + 1] += magnitudes[i] * fracBin
                
                let phaseDiff = phases[i] - lastInputPhases[i]
                lastInputPhases[i] = phases[i]
                
                let expectedPhaseDiff = 2.0 * .pi * Float(i) * Float(hopSize) / Float(fftSize)
                var deltaPhase = phaseDiff - expectedPhaseDiff
                
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
