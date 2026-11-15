import Accelerate
import Atomics
import AudioToolbox
import CoreAudio
import Darwin
import Foundation

public enum TapCaptureError: Error, Equatable, LocalizedError {
    /// A global tap mutes the whole Mac; the test process may never create one.
    case globalTapRefusedInTests
    /// Resonance's own audio process was not found, so a global tap would capture its own output (feedback).
    case ownProcessNotFound

    public var errorDescription: String? {
        switch self {
        case .globalTapRefusedInTests: return "A system-wide tap is not allowed inside tests."
        case .ownProcessNotFound: return "Resonance could not identify its own audio process, so it did not start the capture."
        }
    }
}

/// The capture side of the engine: a Core Audio process tap in a private aggregate device that holds only the tap
/// (no clock sub-device, so capture does not depend on the output device), read by a C IOProc that writes into the
/// `DriftCompensatedBuffer` with no lock or allocation.
///
/// Mute behavior `muted` (HQ-433 step 0): the tapped audio is silenced while the tap exists, and Core Audio drops a
/// dead client's tap within 100 ms, so a crash gives the original audio back. The engine creates the tap only after
/// its output is running.
@available(macOS 14.4, *)
@MainActor
public final class TapCapture: CaptureSource {
    public enum Target: Equatable, Sendable {
        /// These process objects only (tests).
        case processes([AudioObjectID])
        /// Every process except Resonance itself (the app).
        case systemExcludingSelf
    }

    public let target: Target
    public let muteBehavior: CATapMuteBehavior
    public private(set) var isRunning = false

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var rate: Double = 0
    private var context: TapCaptureContext?
    private var buffer: DriftCompensatedBuffer?

    public init(target: Target, muteBehavior: CATapMuteBehavior = .muted) {
        if case .processes(let list) = target { precondition(!list.isEmpty, "an empty process list would be a global tap") }
        self.target = target
        self.muteBehavior = muteBehavior
    }

    public var isGlobal: Bool { target == .systemExcludingSelf }

    // MARK: CaptureSource

    public func prepare() throws -> Double {
        if tapID != kAudioObjectUnknown { return rate }
        let description: CATapDescription
        switch target {
        case .processes(let list):
            description = CATapDescription(stereoMixdownOfProcesses: list)
        case .systemExcludingSelf:
            guard !Self.runningUnderTests else { throw TapCaptureError.globalTapRefusedInTests }
            guard let own = try CoreAudioObjects.processObject(pid: getpid()) else { throw TapCaptureError.ownProcessNotFound }
            description = CATapDescription(stereoGlobalTapButExcludeProcesses: [own])
        }
        description.uuid = UUID()
        description.name = "Resonance"
        description.isPrivate = true
        description.muteBehavior = muteBehavior

        var newTap = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(description, &newTap), "AudioHardwareCreateProcessTap")
        tapID = newTap
        do {
            let format = try CoreAudioObjects.read(tapID, kAudioTapPropertyFormat, initial: AudioStreamBasicDescription())
            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Resonance Capture",
                kAudioAggregateDeviceUIDKey: "resonance.capture.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true,
                ]],
            ]
            var newAggregate = AudioObjectID(kAudioObjectUnknown)
            try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &newAggregate),
                      "AudioHardwareCreateAggregateDevice")
            aggregateID = newAggregate
            let aggregateRate = (try? CoreAudioObjects.nominalSampleRate(of: aggregateID)) ?? 0
            rate = aggregateRate > 0 ? aggregateRate : format.mSampleRate
        } catch {
            teardown()
            throw error
        }
        return rate
    }

    public func start(into buffer: DriftCompensatedBuffer) throws {
        _ = try prepare()
        guard !isRunning else { return }
        let context = TapCaptureContext(buffer: buffer)
        self.context = context
        self.buffer = buffer
        _ = Unmanaged.passRetained(context) // released in teardown, after the IOProc is destroyed
        var newProc: AudioDeviceIOProcID?
        do {
            try check(AudioDeviceCreateIOProcID(aggregateID, tapCaptureIOProc, Unmanaged.passUnretained(context).toOpaque(),
                                                &newProc), "AudioDeviceCreateIOProcID")
            procID = newProc
            try check(AudioDeviceStart(aggregateID, procID), "AudioDeviceStart")
        } catch {
            teardown()
            throw error
        }
        isRunning = true
    }

    public func stop() { teardown() }

    public func rebuild() throws -> Double {
        let lastBuffer = buffer
        let wasRunning = isRunning
        teardown()
        let newRate = try prepare()
        if wasRunning, let lastBuffer { try start(into: lastBuffer) }
        return newRate
    }

    public func currentSampleRate() -> Double? {
        guard tapID != kAudioObjectUnknown,
              let format = try? CoreAudioObjects.read(tapID, kAudioTapPropertyFormat, initial: AudioStreamBasicDescription()),
              format.mSampleRate > 0
        else { return nil }
        return format.mSampleRate
    }

    public func currentHealth() -> CaptureHealth {
        guard let context, rate > 0 else { return CaptureHealth(signalSeen: false, silentSeconds: 0) }
        return CaptureHealth(signalSeen: context.signalSeen.load(ordering: .relaxed),
                             silentSeconds: Double(context.zeroFrames.load(ordering: .relaxed)) / rate)
    }

    // MARK: Teardown

    /// Stop IO, destroy the IOProc, the aggregate, then the tap (the order the spike verified).
    private func teardown() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                if isRunning { AudioDeviceStop(aggregateID, procID) }
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        if let context { Unmanaged.passUnretained(context).release() }
        context = nil
        procID = nil
        isRunning = false
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        rate = 0
    }

    /// True inside `swift test` (the XCTest bundle or the swift-testing helper).
    static var runningUnderTests: Bool {
        let name = ProcessInfo.processInfo.processName
        return name.hasSuffix("PackageTests") || name.contains("xctest") || name.contains("swiftpm-testing-helper")
            || NSClassFromString("XCTestCase") != nil
    }
}

/// State the IOProc reads and writes. Allocated in `start`, released after the IOProc is destroyed.
final class TapCaptureContext: @unchecked Sendable {
    static let chunkFrames = 4096
    let buffer: DriftCompensatedBuffer
    let left: UnsafeMutablePointer<Float>
    let right: UnsafeMutablePointer<Float>
    let secondsPerTick = HostClock.secondsPerTick
    /// Frames in the current run of exact zeros.
    let zeroFrames = UnsafeAtomic<Int>.create(0)
    let signalSeen = UnsafeAtomic<Bool>.create(false)

    init(buffer: DriftCompensatedBuffer) {
        self.buffer = buffer
        left = .allocate(capacity: Self.chunkFrames)
        right = .allocate(capacity: Self.chunkFrames)
        left.initialize(repeating: 0, count: Self.chunkFrames)
        right.initialize(repeating: 0, count: Self.chunkFrames)
    }

    deinit {
        left.deallocate()
        right.deallocate()
        zeroFrames.destroy()
        signalSeen.destroy()
    }

    /// Runs on the HAL IO thread. Accepts one interleaved buffer (stereo or mono) or two mono buffers.
    func process(_ list: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        guard buffers.count > 0, let first = buffers[0].mData else { return }
        let channels = max(Int(buffers[0].mNumberChannels), 1)
        let samples = Int(buffers[0].mDataByteSize) / MemoryLayout<Float>.size
        let frames = samples / channels
        guard frames > 0 else { return }
        let a = first.assumingMemoryBound(to: Float.self)
        let b: UnsafeMutablePointer<Float>? = channels == 1 && buffers.count > 1
            ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil

        var peak: Float = 0
        vDSP_maxmgv(a, 1, &peak, vDSP_Length(samples))
        if let b {
            var peakB: Float = 0
            vDSP_maxmgv(b, 1, &peakB, vDSP_Length(frames))
            peak = max(peak, peakB)
        }
        if peak > 0 {
            zeroFrames.store(0, ordering: .relaxed)
            signalSeen.store(true, ordering: .relaxed)
        } else {
            zeroFrames.wrappingIncrement(by: frames, ordering: .relaxed)
        }

        let now = Double(mach_absolute_time()) * secondsPerTick
        var done = 0
        while done < frames {
            let n = min(Self.chunkFrames, frames - done)
            if channels >= 2 {
                let base = a + done * channels
                for i in 0..<n {
                    left[i] = base[i * channels]
                    right[i] = base[i * channels + 1]
                }
            } else {
                (left).update(from: a + done, count: n)
                (right).update(from: (b ?? a) + done, count: n)
            }
            buffer.write(left: left, right: right, frameCount: n, hostTime: now)
            done += n
        }
    }
}

/// The C IOProc: `AudioDeviceCreateIOProcID`, not the block-and-queue variant (no dispatch on the IO thread).
private func tapCaptureIOProc(_ device: AudioObjectID, _ now: UnsafePointer<AudioTimeStamp>,
                              _ input: UnsafePointer<AudioBufferList>, _ inputTime: UnsafePointer<AudioTimeStamp>,
                              _ output: UnsafeMutablePointer<AudioBufferList>, _ outputTime: UnsafePointer<AudioTimeStamp>,
                              _ clientData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let clientData else { return noErr }
    Unmanaged<TapCaptureContext>.fromOpaque(clientData).takeUnretainedValue().process(input)
    return noErr
}
