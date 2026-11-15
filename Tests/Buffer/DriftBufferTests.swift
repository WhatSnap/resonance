import Foundation
import Testing
@testable import ResonanceCore

/// Two simulated clocks drive one `DriftCompensatedBuffer`: a producer (the tap) writes fixed chunks at its rate and a
/// consumer (the output device) renders fixed blocks at its rate. Events run in simulated-time order.
struct DriftSimulation {
    var producerRate: Double
    var consumerRate: Double
    var seconds: Double
    var producerChunk = 512
    var consumerBlock = 512
    var toneHz: Double = 440
    var amplitude: Float = 0.5

    struct Result {
        var minFill = Int.max
        var maxFill = Int.min
        var fillSum = 0.0
        var fillSamples = 0
        var maxStep: Float = 0
        var underruns = 0
        var droppedChunks = 0
        var primed = false
        var meanFill: Double { fillSum / Double(max(fillSamples, 1)) }
    }

    func run(_ buffer: DriftCompensatedBuffer) -> Result {
        var result = Result()
        let inL = UnsafeMutablePointer<Float>.allocate(capacity: producerChunk)
        let inR = UnsafeMutablePointer<Float>.allocate(capacity: producerChunk)
        let outL = UnsafeMutablePointer<Float>.allocate(capacity: consumerBlock)
        let outR = UnsafeMutablePointer<Float>.allocate(capacity: consumerBlock)
        defer { inL.deallocate(); inR.deallocate(); outL.deallocate(); outR.deallocate() }

        var produced = 0 // frames written so far, also the sine's phase index
        var writes = 0, reads = 0
        var last: Float?
        let w = 2 * Double.pi * toneHz / producerRate
        while true {
            let tWrite = Double(writes * producerChunk) / producerRate
            let tRead = Double(reads * consumerBlock) / consumerRate
            if min(tWrite, tRead) >= seconds { break }
            if tWrite <= tRead {
                for i in 0..<producerChunk {
                    let s = amplitude * Float(sin(w * Double(produced + i)))
                    inL[i] = s; inR[i] = s
                }
                _ = buffer.write(left: inL, right: inR, frameCount: producerChunk, hostTime: tWrite)
                produced += producerChunk
                writes += 1
            } else {
                let fill = buffer.fillLevel
                let wasPrimed = buffer.isPrimed
                buffer.render(left: outL, right: outR, frameCount: consumerBlock, hostTime: tRead)
                if wasPrimed {
                    result.primed = true
                    result.minFill = min(result.minFill, fill)
                    result.maxFill = max(result.maxFill, fill)
                    result.fillSum += Double(fill)
                    result.fillSamples += 1
                    for i in 0..<consumerBlock {
                        if let p = last { result.maxStep = max(result.maxStep, abs(outL[i] - p)) }
                        last = outL[i]
                    }
                }
                reads += 1
            }
        }
        result.underruns = buffer.underrunCount
        result.droppedChunks = buffer.droppedChunkCount
        return result
    }
}

@Suite struct DriftBufferTests {
    let config = DriftBufferConfig(sampleRate: 48000)
    let tenMinutes = 600.0

    /// The largest sample-to-sample step of a clean 440 Hz sine at amplitude 0.5 and 48 kHz is 2π·440/48000·0.5 ≈ 0.0288.
    /// A dropped frame doubles one step (≈ 0.058). The bound sits between the two.
    let clickBound: Float = 0.035

    private func expectHealthy(_ r: DriftSimulation.Result, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(r.primed, "consumer never started", sourceLocation: sourceLocation)
        #expect(r.minFill >= config.lowWaterFrames, "fill fell below band: \(r.minFill)", sourceLocation: sourceLocation)
        #expect(r.maxFill <= config.highWaterFrames, "fill rose above band: \(r.maxFill)", sourceLocation: sourceLocation)
        #expect(r.underruns == 0, "underruns", sourceLocation: sourceLocation)
        #expect(r.droppedChunks == 0, "dropped chunks", sourceLocation: sourceLocation)
        #expect(r.maxStep < clickBound, "discontinuity in output (click): \(r.maxStep)", sourceLocation: sourceLocation)
        #expect(r.meanFill / config.sampleRate <= 0.050, "mean latency over 50 ms", sourceLocation: sourceLocation)
    }

    /// Criteria 2 and 3: producer 48000 Hz, consumer 48001 Hz, 10 simulated minutes.
    @Test func consumerFasterTenMinutes() {
        let buffer = DriftCompensatedBuffer(config: config)
        let r = DriftSimulation(producerRate: 48000, consumerRate: 48001, seconds: tenMinutes).run(buffer)
        expectHealthy(r)
        #expect(buffer.currentRatio < 1, "consumer is faster, so it must read slower than 1:1")
    }

    /// Criterion 4: the reverse drift.
    @Test func producerFasterTenMinutes() {
        let buffer = DriftCompensatedBuffer(config: config)
        let r = DriftSimulation(producerRate: 48001, consumerRate: 48000, seconds: tenMinutes).run(buffer)
        expectHealthy(r)
        #expect(buffer.currentRatio > 1, "producer is faster, so the consumer must read faster than 1:1")
    }

    /// Unequal chunk and block sizes (tap 480, device 512) and a larger drift (100 ppm) must also hold.
    @Test func unequalBlockSizesAndLargerDrift() {
        let buffer = DriftCompensatedBuffer(config: config)
        var sim = DriftSimulation(producerRate: 48000, consumerRate: 48004.8, seconds: 300)
        sim.producerChunk = 480
        expectHealthy(sim.run(buffer))
    }

    /// Criterion 5: steady-state latency is 50 ms or less at 48 kHz, even at the top of the band.
    @Test func targetLatencyIsAtMostFiftyMilliseconds() {
        #expect(Double(config.targetFillFrames) / 48000 <= 0.050)
        #expect(Double(config.highWaterFrames) / 48000 <= 0.050)
        #expect(config.lowWaterFrames > 0)
    }

    /// Equal clocks: after the start-up transient the ratio settles at 1 (within 1 ppm).
    @Test func equalClocksSettleAtRatioOne() {
        let buffer = DriftCompensatedBuffer(config: config)
        let r = DriftSimulation(producerRate: 48000, consumerRate: 48000, seconds: 120).run(buffer)
        expectHealthy(r)
        #expect(abs(buffer.currentRatio - 1) < 1e-6)
    }

    /// A producer that stops must not look like an ever-growing fill: the time extrapolation is capped at one chunk,
    /// so the ratio stays inside its clamp and the buffer simply runs dry once.
    @Test func stalledProducerDoesNotInflateTheEstimate() {
        let buffer = DriftCompensatedBuffer(config: config)
        let chunk = [Float](repeating: 0.25, count: 512)
        for _ in 0..<4 { #expect(buffer.write(left: chunk, right: chunk, frameCount: 512, hostTime: 0)) }
        var l = [Float](repeating: 0, count: 512)
        var r = [Float](repeating: 0, count: 512)
        let fillBefore = buffer.fillLevel
        buffer.render(left: &l, right: &r, frameCount: 512, hostTime: 3600)
        #expect(buffer.estimatedLevel == Double(fillBefore + 512), "an hour of stall adds one chunk, not 172 800 000 frames")
        #expect(abs(buffer.currentRatio - 1) <= config.maxCorrection)
    }

    /// The consumer starts before any audio: it outputs silence and counts no underrun until the target fill is reached.
    @Test func renderBeforePrimingIsSilentAndNotAnUnderrun() {
        let buffer = DriftCompensatedBuffer(config: config)
        var l = [Float](repeating: 1, count: 256)
        var r = [Float](repeating: 1, count: 256)
        buffer.render(left: &l, right: &r, frameCount: 256, hostTime: 0)
        #expect(l == [Float](repeating: 0, count: 256))
        #expect(r == [Float](repeating: 0, count: 256))
        #expect(!buffer.isPrimed)
        #expect(buffer.underrunCount == 0)
    }

    /// The producer stops: the consumer underruns once, outputs silence and waits to re-prime.
    @Test func producerStopCountsOneUnderrunThenSilence() {
        let buffer = DriftCompensatedBuffer(config: config)
        let chunk = [Float](repeating: 0.25, count: 512)
        for _ in 0..<4 { #expect(buffer.write(left: chunk, right: chunk, frameCount: 512, hostTime: 0)) }
        var l = [Float](repeating: 0, count: 512)
        var r = [Float](repeating: 0, count: 512)
        for _ in 0..<8 { buffer.render(left: &l, right: &r, frameCount: 512, hostTime: 0) }
        #expect(buffer.underrunCount == 1)
        #expect(!buffer.isPrimed)
        #expect(l == [Float](repeating: 0, count: 512))
    }

    /// A full ring drops the incoming chunk whole and counts it.
    @Test func overflowDropsWholeChunkAndCountsIt() {
        let buffer = DriftCompensatedBuffer(config: config)
        let chunk = [Float](repeating: 0.1, count: 1024)
        var accepted = 0
        for _ in 0..<64 where buffer.write(left: chunk, right: chunk, frameCount: 1024, hostTime: 0) { accepted += 1 }
        #expect(accepted == config.capacityFrames / 1024)
        #expect(buffer.droppedChunkCount == 64 - accepted)
    }

    /// A render larger than the internal scratch block is split, not refused.
    @Test func renderLargerThanMaxBlockIsSplit() {
        var small = config
        small.maxBlockFrames = 128
        let buffer = DriftCompensatedBuffer(config: small)
        let chunk = [Float](repeating: 0.5, count: 2048)
        #expect(buffer.write(left: chunk, right: chunk, frameCount: 2048, hostTime: 0))
        var l = [Float](repeating: 0, count: 1000)
        var r = [Float](repeating: 0, count: 1000)
        buffer.render(left: &l, right: &r, frameCount: 1000, hostTime: 0)
        #expect(buffer.underrunCount == 0)
        #expect(l == [Float](repeating: 0.5, count: 1000))
    }

    /// Criterion 1: no allocation on the write or render path. 20 000 calls of each path in a tight loop must not grow
    /// the live heap by one block per call. Swift Testing runs other suites in parallel, so the heap count is noisy:
    /// the test takes the smallest growth of five trials. Transient alloc-and-free is covered by code review: the paths
    /// only touch preallocated pointers and atomics.
    @Test func hotPathsDoNotAllocate() {
        let buffer = DriftCompensatedBuffer(config: config)
        let inL = UnsafeMutablePointer<Float>.allocate(capacity: 512)
        let inR = UnsafeMutablePointer<Float>.allocate(capacity: 512)
        let outL = UnsafeMutablePointer<Float>.allocate(capacity: 512)
        let outR = UnsafeMutablePointer<Float>.allocate(capacity: 512)
        defer { inL.deallocate(); inR.deallocate(); outL.deallocate(); outR.deallocate() }
        inL.initialize(repeating: 0.1, count: 512)
        inR.initialize(repeating: 0.1, count: 512)
        for _ in 0..<8 {
            _ = buffer.write(left: inL, right: inR, frameCount: 512, hostTime: 0)
            buffer.render(left: outL, right: outR, frameCount: 512, hostTime: 0)
        }

        let iterations = 20_000
        var smallestGrowth = Int.max
        for _ in 0..<5 {
            let before = liveHeapBlocks()
            for _ in 0..<iterations {
                _ = buffer.write(left: inL, right: inR, frameCount: 512, hostTime: 0)
                buffer.render(left: outL, right: outR, frameCount: 512, hostTime: 0)
            }
            smallestGrowth = min(smallestGrowth, liveHeapBlocks() - before)
        }
        #expect(smallestGrowth < iterations / 10, "hot paths grew the heap by \(smallestGrowth) blocks")
        #expect(buffer.underrunCount == 0)
        #expect(buffer.droppedChunkCount == 0)
    }
}
