import Foundation
import Testing
@testable import ResonanceCore

private func sine(_ frequency: Double, sampleRate: Double, seconds: Double, amplitude: Float = 0.25) -> [Float] {
    let count = Int(sampleRate * seconds)
    return (0..<count).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / sampleRate)) }
}

@Suite struct SignalAnalysisTests {
    @Test func rmsOfSilenceIsZero() {
        #expect(SignalAnalysis.rms([Float](repeating: 0, count: 1024)) == 0)
        #expect(SignalAnalysis.rms([]) == 0)
    }

    @Test func rmsOfSineIsAmplitudeOverRootTwo() {
        let samples = sine(1000, sampleRate: 48000, seconds: 1, amplitude: 0.5)
        #expect(abs(Double(SignalAnalysis.rms(samples)) - 0.5 / 2.0.squareRoot()) < 0.001)
    }

    @Test(arguments: [440.0, 997.0, 1234.5], [44100.0, 48000.0])
    func peakFrequencyWithinHalfHertz(frequency: Double, rate: Double) throws {
        let samples = sine(frequency, sampleRate: rate, seconds: 2)
        let peak = try #require(SignalAnalysis.peakFrequency(samples, sampleRate: rate))
        #expect(abs(peak - frequency) < 0.5)
    }

    @Test func peakFrequencyOfSilenceIsNil() {
        #expect(SignalAnalysis.peakFrequency([Float](repeating: 0, count: 8192), sampleRate: 48000) == nil)
    }

    @Test func magnitudeAtFrequencySeparatesToneFromSilence() {
        let tone = sine(997, sampleRate: 48000, seconds: 1)
        let silence = [Float](repeating: 0, count: tone.count)
        #expect(SignalAnalysis.magnitude(at: 997, in: tone, sampleRate: 48000) > 0.1)
        #expect(SignalAnalysis.magnitude(at: 997, in: silence, sampleRate: 48000) == 0)
    }

    @Test func channelTakesOneChannelOfInterleaved() {
        let interleaved: [Float] = [1, 10, 2, 20, 3, 30]
        #expect(SignalAnalysis.channel(0, of: interleaved, channels: 2) == [1, 2, 3])
        #expect(SignalAnalysis.channel(1, of: interleaved, channels: 2) == [10, 20, 30])
    }
}

@Suite struct SilenceWatchdogTests {
    private func feed(_ watchdog: inout SilenceWatchdog, _ peaks: [Float]) -> [Bool] {
        peaks.map { watchdog.observe(peak: $0) }
    }

    @Test func firesAfterConsecutiveSilentBuffersOnly() {
        var watchdog = SilenceWatchdog(silentBuffersBeforeRebuild: 3)
        // Signal resets the count; fires once on the third silent buffer in a row.
        #expect(feed(&watchdog, [0, 0, 0.2, 0, 0, 0, 0]) == [false, false, false, false, false, true, false])
    }

    @Test func waitsForFirstSignalWhenArmedOnSignal() {
        // A source that has not started yet is silence, not a broken tap.
        var watchdog = SilenceWatchdog(silentBuffersBeforeRebuild: 2, armOnFirstSignal: true)
        #expect(feed(&watchdog, [Float](repeating: 0, count: 10)).allSatisfy { !$0 })
        #expect(feed(&watchdog, [0.1, 0, 0]) == [false, false, true])
    }

    @Test func resetStartsOver() {
        var watchdog = SilenceWatchdog(silentBuffersBeforeRebuild: 2)
        _ = feed(&watchdog, [0])
        watchdog.reset()
        #expect(feed(&watchdog, [0, 0]) == [false, true])
    }
}
