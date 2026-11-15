import Darwin
import Foundation
import Testing
@testable import ResonanceCore

@Suite struct SPSCRingBufferTests {
    @Test func capacityRoundsUpToPowerOfTwo() {
        let ring = SPSCRingBuffer(capacityFrames: 1000)
        #expect(ring.capacity == 1024)
        #expect(ring.fillLevel == 0)
    }

    @Test func writeThenReadKeepsOrderAcrossWrap() {
        let ring = SPSCRingBuffer(capacityFrames: 8)
        var l = [Float](repeating: 0, count: 6)
        var r = [Float](repeating: 0, count: 6)
        var next: Float = 0
        // Three rounds of 6 frames through an 8-frame ring force the wrap.
        for _ in 0..<3 {
            for i in 0..<6 { l[i] = next; r[i] = -next; next += 1 }
            #expect(ring.write(left: l, right: r, frameCount: 6))
            var ol = [Float](repeating: .nan, count: 6)
            var or = [Float](repeating: .nan, count: 6)
            #expect(ring.read(left: &ol, right: &or, frameCount: 6) == 6)
            #expect(ol == l)
            #expect(or == r)
        }
    }

    @Test func writeRefusesAChunkThatDoesNotFit() {
        let ring = SPSCRingBuffer(capacityFrames: 8)
        let six = [Float](repeating: 1, count: 6)
        #expect(ring.write(left: six, right: six, frameCount: 6))
        #expect(!ring.write(left: six, right: six, frameCount: 6))
        #expect(ring.fillLevel == 6)
    }

    @Test func peekDoesNotConsumeUntilAdvance() {
        let ring = SPSCRingBuffer(capacityFrames: 8)
        let a: [Float] = [1, 2, 3, 4]
        #expect(ring.write(left: a, right: a, frameCount: 4))
        var ol = [Float](repeating: 0, count: 8)
        var or = [Float](repeating: 0, count: 8)
        #expect(ring.peek(left: &ol, right: &or, maxFrames: 8) == 4)
        #expect(ring.fillLevel == 4)
        ring.advance(by: 3)
        #expect(ring.fillLevel == 1)
        #expect(ring.read(left: &ol, right: &or, frameCount: 4) == 1)
        #expect(ol[0] == 4)
    }

    /// Criterion 1 (part): both paths run at once on two threads in a tight loop, with no lock.
    /// Every frame carries its sequence number, so a torn or reordered read fails the test.
    @Test func concurrentProducerAndConsumerTightLoop() {
        let ring = SPSCRingBuffer(capacityFrames: 1024)
        let total = 2_000_000
        let chunk = 64
        let done = DispatchSemaphore(value: 0)
        let errors = ErrorBox()

        let producer = Thread {
            let l = UnsafeMutablePointer<Float>.allocate(capacity: chunk)
            let r = UnsafeMutablePointer<Float>.allocate(capacity: chunk)
            defer { l.deallocate(); r.deallocate() }
            var sent = 0
            while sent < total {
                for i in 0..<chunk { l[i] = Float(sent + i); r[i] = -Float(sent + i) }
                while !ring.write(left: l, right: r, frameCount: chunk) {} // spin, no lock
                sent += chunk
            }
            done.signal()
        }
        let consumer = Thread {
            let l = UnsafeMutablePointer<Float>.allocate(capacity: 100)
            let r = UnsafeMutablePointer<Float>.allocate(capacity: 100)
            defer { l.deallocate(); r.deallocate() }
            var expected = 0
            while expected < total {
                let n = ring.read(left: l, right: r, frameCount: 100)
                for i in 0..<n where l[i] != Float(expected + i) || r[i] != -Float(expected + i) {
                    errors.record(expected + i)
                }
                expected += n
            }
            done.signal()
        }
        producer.start()
        consumer.start()
        #expect(done.wait(timeout: .now() + 60) == .success)
        #expect(done.wait(timeout: .now() + 60) == .success)
        #expect(errors.count == 0, "first bad frame: \(errors.first ?? -1)")
        #expect(ring.fillLevel == 0)
    }
}

/// Collects mismatches from the consumer thread for the test to read after the join.
final class ErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    private var _first: Int?
    var count: Int { lock.lock(); defer { lock.unlock() }; return _count }
    var first: Int? { lock.lock(); defer { lock.unlock() }; return _first }
    func record(_ frame: Int) {
        lock.lock(); defer { lock.unlock() }
        _count += 1
        if _first == nil { _first = frame }
    }
}

/// Live heap blocks across all malloc zones. A path that allocates and keeps memory per call shows up here.
func liveHeapBlocks() -> Int {
    var stats = malloc_statistics_t()
    malloc_zone_statistics(nil, &stats)
    return Int(stats.blocks_in_use)
}
