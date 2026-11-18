import Atomics

/// Single-producer single-consumer lock-free ring buffer for non-interleaved Float32 stereo.
///
/// One thread calls `write`; one other thread calls `read`, `peek` and `advance`. `fillLevel` may be read from either.
/// Storage is allocated once in `init`. The hot paths take no lock and allocate nothing: they load and store two
/// atomic counters and copy with `memcpy`-style pointer updates.
///
/// The counters are monotonic frame indices (`Int`, 64-bit: no wrap in practice). The producer publishes with a
/// releasing store of `head` after copying; the consumer acquires `head` before copying and publishes `tail` with a
/// releasing store after it is done with the slots, so the producer never overwrites frames still being read.
public final class SPSCRingBuffer: @unchecked Sendable {
    public let capacity: Int
    private let mask: Int
    private let left: UnsafeMutablePointer<Float>
    private let right: UnsafeMutablePointer<Float>
    private let head: UnsafeAtomic<Int> // next frame the producer writes
    private let tail: UnsafeAtomic<Int> // next frame the consumer reads

    /// - Parameter capacityFrames: rounded up to the next power of two.
    public init(capacityFrames: Int) {
        precondition(capacityFrames > 0)
        var cap = 1
        while cap < capacityFrames { cap <<= 1 }
        capacity = cap
        mask = cap - 1
        left = .allocate(capacity: cap)
        right = .allocate(capacity: cap)
        left.initialize(repeating: 0, count: cap)
        right.initialize(repeating: 0, count: cap)
        head = .create(0)
        tail = .create(0)
    }

    deinit {
        left.deallocate()
        right.deallocate()
        head.destroy()
        tail.destroy()
    }

    /// Frames available to read. Exact on the consumer thread; a lower bound of free space on the producer thread.
    public var fillLevel: Int {
        let t = tail.load(ordering: .acquiring)
        let h = head.load(ordering: .acquiring)
        return h - t
    }

    // MARK: Producer

    /// Writes all `frameCount` frames, or none if they do not fit. Returns whether it wrote.
    @discardableResult
    public func write(left srcL: UnsafePointer<Float>, right srcR: UnsafePointer<Float>, frameCount: Int) -> Bool {
        let h = head.load(ordering: .relaxed)
        let t = tail.load(ordering: .acquiring)
        guard frameCount >= 0, frameCount <= capacity - (h - t) else { return false }
        let start = h & mask
        let first = min(frameCount, capacity - start)
        (left + start).update(from: srcL, count: first)
        (right + start).update(from: srcR, count: first)
        if first < frameCount {
            left.update(from: srcL + first, count: frameCount - first)
            right.update(from: srcR + first, count: frameCount - first)
        }
        head.store(h + frameCount, ordering: .releasing)
        return true
    }

    // MARK: Consumer

    /// Copies up to `maxFrames` frames without consuming them. Returns the count copied.
    public func peek(left dstL: UnsafeMutablePointer<Float>, right dstR: UnsafeMutablePointer<Float>, maxFrames: Int) -> Int {
        let t = tail.load(ordering: .relaxed)
        let h = head.load(ordering: .acquiring)
        let n = max(0, min(maxFrames, h - t))
        let start = t & mask
        let first = min(n, capacity - start)
        dstL.update(from: left + start, count: first)
        dstR.update(from: right + start, count: first)
        if first < n {
            (dstL + first).update(from: left, count: n - first)
            (dstR + first).update(from: right, count: n - first)
        }
        return n
    }

    /// Consumes `frames` frames. Must not exceed what the last `peek` returned.
    public func advance(by frames: Int) {
        let t = tail.load(ordering: .relaxed)
        tail.store(t + frames, ordering: .releasing)
    }

    /// Copies and consumes up to `frameCount` frames. Returns the count read.
    @discardableResult
    public func read(left dstL: UnsafeMutablePointer<Float>, right dstR: UnsafeMutablePointer<Float>, frameCount: Int) -> Int {
        let n = peek(left: dstL, right: dstR, maxFrames: frameCount)
        advance(by: n)
        return n
    }
}
