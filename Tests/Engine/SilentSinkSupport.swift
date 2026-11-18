import CoreAudio
import Darwin
import Foundation
import Testing
@testable import ResonanceCore

/// Every suite that plays to or reads BlackHole is nested here, so they run one at a time: two at once would sum on
/// the sink and spoil each other's levels. (`.serialized` applies to nested suites.)
@Suite(.serialized) enum BlackHoleSuites {}

/// BlackHole 2ch as a silent sink: what the engine plays there loops back to BlackHole's input and nowhere else.
enum SilentSink {
    static let uid = "BlackHole2ch_UID"

    /// The sink can be used: BlackHole is installed and the old Resonance app (which plays BlackHole's input on the
    /// speakers) is not running.
    static var available: Bool {
        guard (try? CoreAudioObjects.device(withUID: uid)) != nil else { return false }
        return (try? SpikeSupport.resonanceAppIsRunning()) == false
    }

    static func device() throws -> AudioDeviceID {
        guard let id = try CoreAudioObjects.device(withUID: uid) else { throw CoreAudioError("BlackHole missing", -1) }
        return id
    }
}

/// A capture stand-in: a thread that writes a sine into the buffer in real time, 512-frame chunks.
@MainActor
final class SineCapture: CaptureSource {
    let frequency: Double
    let rate: Double
    private(set) var isRunning = false
    private(set) var startCount = 0
    private(set) var prepareCount = 0
    private var thread: Thread?
    private let stopFlag = StopFlag()

    final class StopFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var stopped = false
        var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
        func set(_ value: Bool) { lock.lock(); stopped = value; lock.unlock() }
    }

    init(frequency: Double = 440, rate: Double = 48_000) {
        self.frequency = frequency
        self.rate = rate
    }

    func prepare() throws -> Double {
        prepareCount += 1
        return rate
    }

    func start(into buffer: DriftCompensatedBuffer) throws {
        startCount += 1
        stopFlag.set(false)
        let flag = stopFlag
        let rate = rate
        let step = 2 * Double.pi * frequency / rate
        let thread = Thread {
            let chunk = 512
            let left = UnsafeMutablePointer<Float>.allocate(capacity: chunk)
            let right = UnsafeMutablePointer<Float>.allocate(capacity: chunk)
            defer { left.deallocate(); right.deallocate() }
            var phase = 0.0
            let start = HostClock.now()
            var written = 0
            while !flag.isStopped {
                for i in 0..<chunk {
                    let s = Float(0.25 * sin(phase))
                    left[i] = s
                    right[i] = s
                    phase += step
                }
                phase = phase.truncatingRemainder(dividingBy: 2 * .pi)
                written += chunk
                let due = start + Double(written) / rate
                let wait = due - HostClock.now()
                if wait > 0 { usleep(useconds_t(wait * 1_000_000)) }
                buffer.write(left: left, right: right, frameCount: chunk, hostTime: HostClock.now())
            }
        }
        thread.qualityOfService = .userInteractive
        thread.start()
        self.thread = thread
        isRunning = true
    }

    func stop() {
        stopFlag.set(true)
        thread = nil
        isRunning = false
    }

    func rebuild() throws -> Double { rate }
    func currentSampleRate() -> Double? { isRunning ? rate : nil }
    func currentHealth() -> CaptureHealth { CaptureHealth(signalSeen: true, silentSeconds: 0) }
}
