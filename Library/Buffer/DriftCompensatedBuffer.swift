import Atomics

/// Settings for `DriftCompensatedBuffer`. All sizes are in frames at `sampleRate`.
public struct DriftBufferConfig: Sendable {
    public var sampleRate: Double
    /// Level the controller holds, as latency. 30 ms = 1440 frames at 48 kHz. The frames actually in the ring sit
    /// between the estimated level minus one producer chunk and the level, and must stay above one consumer block, so
    /// the target must exceed producer chunk + consumer block (512 + 512 here) with margin.
    public var targetLatencySeconds: Double = 0.030
    /// Allowed distance of the ring's fill level (measured by the consumer before each render) from the target.
    /// It covers one producer chunk below the target plus margin.
    public var bandFrames: Int = 640
    public var capacityFrames: Int = 8192
    /// Largest block rendered in one pass. Larger renders are split. Sizes the scratch buffers.
    public var maxBlockFrames: Int = 4096
    /// Ratio correction per unit of relative fill error: ratio = 1 + gain · (fill − target) / target.
    public var correctionGain: Double = 0.002
    /// Largest ratio correction: ±0.1 % (1.7 cents, below hearing). Covers clock offsets up to ±1000 ppm.
    public var maxCorrection: Double = 0.001
    /// Smoothing of the measured fill level per render (exponential moving average weight).
    public var fillSmoothing: Double = 0.05

    public init(sampleRate: Double) { self.sampleRate = sampleRate }

    public var targetFillFrames: Int { Int((sampleRate * targetLatencySeconds).rounded()) }
    public var lowWaterFrames: Int { targetFillFrames - bandFrames }
    public var highWaterFrames: Int { targetFillFrames + bandFrames }
}

/// A stereo SPSC buffer between two clocks (tap capture → output device) that holds a target fill level and absorbs
/// clock drift without clicks.
///
/// **Measuring the level.** A frame count alone cannot see drift: with equal chunk and block sizes the producer and
/// consumer alternate one-to-one, and the fill seen at each read stays constant for minutes while the drift
/// accumulates in the timing between the two clocks, until two reads land back to back and the buffer runs dry. So
/// both sides pass a host time, the producer publishes the time of its last write, and the consumer estimates the
/// continuous level: frames in the ring plus the frames the producer has captured since that write (capped at one
/// chunk, so a stalled producer does not look like a full buffer).
///
/// **Drift correction: adaptive resampling, not frame drop/repeat.** The consumer reads input at a ratio slightly off
/// 1:1 (at most ±0.1 %) set by a proportional controller on the smoothed fill level, and interpolates linearly between
/// input frames. Dropping or repeating a frame makes a step in the waveform, which is a click on loud high-frequency
/// content; a 0.1 % rate change is a 1.7-cent pitch change, below hearing, and keeps the waveform continuous. The
/// cost is one linear interpolation per sample.
///
/// Threads: `write` on the producer thread only; `render` on the consumer thread only. Neither locks or allocates.
/// `fillLevel`, `underrunCount` and `droppedChunkCount` may be read from any thread. `isPrimed` and `currentRatio`
/// are consumer state: read them on the consumer thread or after it stops.
public final class DriftCompensatedBuffer: @unchecked Sendable {
    public let config: DriftBufferConfig
    private let ring: SPSCRingBuffer
    private let scratchL: UnsafeMutablePointer<Float>
    private let scratchR: UnsafeMutablePointer<Float>
    private let scratchCapacity: Int
    private let underruns = UnsafeAtomic<Int>.create(0)
    private let drops = UnsafeAtomic<Int>.create(0)

    // Producer's last write, published through a seqlock: odd `writeSeq` means a write is in progress.
    private let writeSeq = UnsafeAtomic<Int>.create(0)
    private let lastWriteTimeBits = UnsafeAtomic<UInt64>.create(0)
    private let lastWriteFrames = UnsafeAtomic<Int>.create(0)

    // Consumer-only state.
    public private(set) var isPrimed = false
    public private(set) var currentRatio = 1.0
    /// The level estimate used by the last render, in frames.
    public private(set) var estimatedLevel = 0.0
    private var smoothedFill = 0.0
    private var phase = 0.0 // position between x0 and x1, in [0, 1)
    private var x0L: Float = 0, x1L: Float = 0, x0R: Float = 0, x1R: Float = 0

    public init(config: DriftBufferConfig) {
        precondition(config.lowWaterFrames > 0 && config.highWaterFrames < config.capacityFrames)
        self.config = config
        ring = SPSCRingBuffer(capacityFrames: config.capacityFrames)
        // One block at the fastest ratio, plus rounding.
        scratchCapacity = Int((Double(config.maxBlockFrames) * (1 + config.maxCorrection)).rounded(.up)) + 2
        scratchL = .allocate(capacity: scratchCapacity)
        scratchR = .allocate(capacity: scratchCapacity)
        scratchL.initialize(repeating: 0, count: scratchCapacity)
        scratchR.initialize(repeating: 0, count: scratchCapacity)
    }

    deinit {
        scratchL.deallocate()
        scratchR.deallocate()
        underruns.destroy()
        drops.destroy()
        writeSeq.destroy()
        lastWriteTimeBits.destroy()
        lastWriteFrames.destroy()
    }

    public var fillLevel: Int { ring.fillLevel }
    /// Renders that ran out of input after the buffer had started.
    public var underrunCount: Int { underruns.load(ordering: .relaxed) }
    /// Producer chunks refused because the ring was full.
    public var droppedChunkCount: Int { drops.load(ordering: .relaxed) }

    // MARK: Producer

    /// Writes one chunk, whole. If it does not fit, it is dropped, counted, and `false` is returned.
    /// - Parameter hostTime: when the chunk's last frame was captured, in seconds of the clock `render` uses too
    ///   (for example the IOProc's input time stamp, converted from host ticks).
    @discardableResult
    public func write(left: UnsafePointer<Float>, right: UnsafePointer<Float>, frameCount: Int, hostTime: Double) -> Bool {
        guard ring.write(left: left, right: right, frameCount: frameCount) else {
            drops.wrappingIncrement(ordering: .relaxed)
            return false
        }
        let seq = writeSeq.load(ordering: .relaxed)
        writeSeq.store(seq &+ 1, ordering: .relaxed)
        atomicMemoryFence(ordering: .releasing)
        lastWriteTimeBits.store(hostTime.bitPattern, ordering: .relaxed)
        lastWriteFrames.store(frameCount, ordering: .relaxed)
        writeSeq.store(seq &+ 2, ordering: .releasing)
        return true
    }

    /// Frames in the ring plus frames captured since the producer's last write. Lock-free: a torn read is retried a
    /// few times, then the plain fill is used.
    private func estimateLevel(fill: Int, at hostTime: Double) -> Double {
        for _ in 0..<4 {
            let s1 = writeSeq.load(ordering: .acquiring)
            if s1 & 1 != 0 { continue }
            let t = Double(bitPattern: lastWriteTimeBits.load(ordering: .relaxed))
            let chunk = lastWriteFrames.load(ordering: .relaxed)
            atomicMemoryFence(ordering: .acquiring)
            guard writeSeq.load(ordering: .relaxed) == s1 else { continue }
            if s1 == 0 { return Double(fill) } // nothing written yet
            let elapsed = min(max(0, (hostTime - t) * config.sampleRate), Double(chunk))
            return Double(fill) + elapsed
        }
        return Double(fill)
    }

    // MARK: Consumer

    /// Fills exactly `frameCount` output frames. Outputs silence until the fill level first reaches the target, and
    /// again after an underrun until it is reached again.
    /// - Parameter hostTime: when the block starts playing (or the IOProc's "now"), same clock as `write`.
    public func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frameCount: Int, hostTime: Double) {
        var done = 0
        while done < frameCount {
            let n = min(config.maxBlockFrames, frameCount - done)
            renderBlock(left + done, right + done, n, hostTime + Double(done) / config.sampleRate)
            done += n
        }
    }

    private func renderBlock(_ outL: UnsafeMutablePointer<Float>, _ outR: UnsafeMutablePointer<Float>, _ n: Int, _ hostTime: Double) {
        let fill = ring.fillLevel
        if !isPrimed {
            guard fill >= config.targetFillFrames else {
                outL.update(repeating: 0, count: n)
                outR.update(repeating: 0, count: n)
                return
            }
            prime()
        }

        let target = Double(config.targetFillFrames)
        estimatedLevel = estimateLevel(fill: fill, at: hostTime)
        smoothedFill += config.fillSmoothing * (estimatedLevel - smoothedFill)
        let correction = config.correctionGain * (smoothedFill - target) / target
        currentRatio = 1 + min(max(correction, -config.maxCorrection), config.maxCorrection)

        let wanted = min(scratchCapacity, Int((phase + Double(n) * currentRatio).rounded(.up)) + 1)
        let available = ring.peek(left: scratchL, right: scratchR, maxFrames: wanted)
        var used = 0
        var p = phase
        for i in 0..<n {
            let f = Float(p)
            outL[i] = x0L + (x1L - x0L) * f
            outR[i] = x0R + (x1R - x0R) * f
            p += currentRatio
            while p >= 1 {
                guard used < available else {
                    // Out of input: count it, silence the rest, and wait to re-prime.
                    (outL + i + 1).update(repeating: 0, count: n - i - 1)
                    (outR + i + 1).update(repeating: 0, count: n - i - 1)
                    ring.advance(by: used)
                    underruns.wrappingIncrement(ordering: .relaxed)
                    isPrimed = false
                    return
                }
                x0L = x1L; x1L = scratchL[used]
                x0R = x1R; x1R = scratchR[used]
                used += 1
                p -= 1
            }
        }
        phase = p
        ring.advance(by: used)
    }

    /// Loads the first two frames into the interpolation window and starts at ratio 1.
    private func prime() {
        _ = ring.read(left: scratchL, right: scratchR, frameCount: 2)
        x0L = scratchL[0]; x1L = scratchL[1]
        x0R = scratchR[0]; x1R = scratchR[1]
        phase = 0
        smoothedFill = Double(config.targetFillFrames)
        currentRatio = 1
        isPrimed = true
    }
}
