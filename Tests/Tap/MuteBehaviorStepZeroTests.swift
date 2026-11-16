import AudioToolbox
import CoreAudio
import Darwin
import Foundation
import Testing
@testable import ResonanceCore

extension BlackHoleSuites {
    /// HQ-433 step 0: settle the tap mute behavior before the engine is wired.
    ///
    /// 0a. A separate process holds a tap on the sine child, then is killed with SIGKILL. Does the child's audio come
    ///     back on its device, and how fast?
    /// 0b. `mutedWhenTapped` (and `muted`, for comparison) measured in 100 ms windows from the moment IO starts, to tell
    ///     a start transient from a steady leak.
    /// Also: whether a tap-only aggregate (no clock sub-device) delivers audio, which lets the engine keep capture and
    /// output on separate clocks.
    ///
    /// Same silence rules as the HQ-429 spike: the child plays only to BlackHole 2ch, the taps list only the child, and
    /// the default output is read before and after. Off unless `RESONANCE_TAP_SPIKE=1`. Findings (JSON) go to
    /// `RESONANCE_STEP0_OUT` when set.
    @Suite(.enabled(if: ProcessInfo.processInfo.environment["RESONANCE_TAP_SPIKE"] == "1"), .serialized)
    struct MuteBehaviorStepZeroTests {
        static let blackHoleUID = BlackHoleSuites.ProcessTapSpikeTests.blackHoleUID
        static let toneHz = BlackHoleSuites.ProcessTapSpikeTests.toneHz
        static let window = 0.1

        @Test func killNineAndHundredMillisecondWindows() async throws {
            guard #available(macOS 14.4, *) else { return }
            let appRunning = try SpikeSupport.resonanceAppIsRunning()
            try #require(!appRunning, "Quit the Resonance app first: it plays BlackHole on the speakers.")
            let blackHoleLookup = try CoreAudioObjects.device(withUID: Self.blackHoleUID)
            let blackHole = try #require(blackHoleLookup, "BlackHole 2ch is required as a silent sink")
            let rate = try CoreAudioObjects.nominalSampleRate(of: blackHole)
            let defaultBefore = try CoreAudioObjects.defaultOutputDevice()

            var findings = StepZeroFindings()
            findings.defaultOutputBefore = try CoreAudioObjects.uid(of: defaultBefore)
            findings.rate = rate

            let child = try SpikeSupport.launchSineChild(deviceUID: Self.blackHoleUID, frequency: Self.toneHz, seconds: 120)
            defer { child.terminate(); child.waitUntilExit() }
            let processLookup = try await SpikeSupport.waitForProcessObject(pid: child.processIdentifier)
            let process = try #require(processLookup, "child never registered with Core Audio")

            let monitor = try LoopbackMonitor(device: blackHole)
            defer { monitor.stop() }
            try await Task.sleep(for: .milliseconds(500))
            findings.referenceLevel = monitor.level(from: monitor.mark() - Int(0.4 * rate), seconds: 0.4,
                                                    frequency: Self.toneHz, rate: rate)

            // 0a: another process taps the child, then dies by SIGKILL.
            for behavior in ["muted", "mutedWhenTapped"] {
                let tapper = try StepZeroSupport.launchTapper(pid: child.processIdentifier, behavior: behavior,
                                                              clock: Self.blackHoleUID)
                try await Task.sleep(for: .milliseconds(700))
                let aliveStart = monitor.mark() - Int(0.4 * rate)
                var run = KillRun(behavior: behavior)
                run.levelWhileTapperAlive = monitor.level(from: aliveStart, seconds: 0.4, frequency: Self.toneHz, rate: rate)
                let killMark = monitor.mark()
                kill(tapper.processIdentifier, SIGKILL)
                tapper.waitUntilExit()
                try await Task.sleep(for: .milliseconds(2500))
                run.windowsAfterKill = monitor.windows(from: killMark, count: 20, seconds: Self.window,
                                                       frequency: Self.toneHz, rate: rate)
                run.levelThreeSecondsLater = monitor.level(from: monitor.mark() - Int(0.4 * rate), seconds: 0.4,
                                                           frequency: Self.toneHz, rate: rate)
                findings.kills.append(run)
                #expect(run.levelWhileTapperAlive < findings.referenceLevel * 0.1,
                        "\(behavior): a tap held by another process mutes the child while it reads")
            }

            // 0b: in-process taps, 100 ms windows from IO start.
            for behavior in [CATapMuteBehavior.mutedWhenTapped, .muted] {
                let capture = ProcessTapCapture(configuration: .init(
                    processes: [process], muteBehavior: behavior, clockDeviceUID: Self.blackHoleUID, name: "Resonance Step0"))
                let before = monitor.mark()
                try await Task.sleep(for: .milliseconds(300))
                let startMark = monitor.mark()
                try capture.start(queue: DispatchQueue(label: "step0.tap", qos: .userInitiated)) { _, _ in }
                try await Task.sleep(for: .milliseconds(2200))
                var run = WindowRun(behavior: SpikeFindings.name(behavior))
                run.levelBeforeStart = monitor.level(from: before, seconds: 0.3, frequency: Self.toneHz, rate: rate)
                run.windowsAfterStart = monitor.windows(from: startMark, count: 20, seconds: Self.window,
                                                        frequency: Self.toneHz, rate: rate)
                capture.stop()
                try await Task.sleep(for: .milliseconds(500))
                run.levelAfterStop = monitor.level(from: monitor.mark() - Int(0.3 * rate), seconds: 0.3,
                                                   frequency: Self.toneHz, rate: rate)
                findings.windows.append(run)
            }

            // Tap-only aggregate: no clock sub-device. Does IO run and carry the tone?
            let tapOnly = try StepZeroSupport.launchTapper(pid: child.processIdentifier, behavior: "muted", clock: "none")
            let report = try StepZeroSupport.readLine(from: tapOnly, prefix: "RMS", timeout: 6)
            kill(tapOnly.processIdentifier, SIGKILL)
            tapOnly.waitUntilExit()
            findings.tapOnlyAggregateReport = report

            let defaultAfter = try CoreAudioObjects.defaultOutputDevice()
            findings.defaultOutputAfter = try CoreAudioObjects.uid(of: defaultAfter)
            #expect(defaultAfter == defaultBefore, "system default output unchanged")
            try findings.write()
        }
    }
}

// MARK: - Findings

struct KillRun: Codable {
    var behavior: String
    var levelWhileTapperAlive = 0.0
    var windowsAfterKill: [Double] = []
    var levelThreeSecondsLater = 0.0
}

struct WindowRun: Codable {
    var behavior: String
    var levelBeforeStart = 0.0
    var windowsAfterStart: [Double] = []
    var levelAfterStop = 0.0
}

struct StepZeroFindings: Codable {
    var defaultOutputBefore = ""
    var defaultOutputAfter = ""
    var rate = 0.0
    var referenceLevel = 0.0
    var kills: [KillRun] = []
    var windows: [WindowRun] = []
    var tapOnlyAggregateReport = ""

    func write() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        print("STEP0-FINDINGS", String(decoding: data, as: UTF8.self))
        if let path = ProcessInfo.processInfo.environment["RESONANCE_STEP0_OUT"] {
            try data.write(to: URL(fileURLWithPath: path))
        }
    }
}

// MARK: - Support

/// Records BlackHole's input (its loopback) continuously, first channel only, so levels can be read on one timeline.
final class LoopbackMonitor: @unchecked Sendable {
    private let device: AudioDeviceID
    private var procID: AudioDeviceIOProcID?
    private let lock = NSLock()
    private var samples: [Float] = []

    init(device: AudioDeviceID) throws {
        self.device = device
        samples.reserveCapacity(48_000 * 60)
        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, device, DispatchQueue(label: "step0.loopback")) { [weak self] _, input, _, _, _ in
            self?.append(input)
        }, "loopback IOProc")
        try check(AudioDeviceStart(device, procID), "loopback start")
    }

    private func append(_ list: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        guard let buffer = buffers.first, let data = buffer.mData else { return }
        let channels = max(Int(buffer.mNumberChannels), 1)
        let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        let floats = data.assumingMemoryBound(to: Float.self)
        lock.lock(); defer { lock.unlock() }
        for i in stride(from: 0, to: count, by: channels) { samples.append(floats[i]) }
    }

    /// Current sample index on the monitor's timeline.
    func mark() -> Int {
        lock.lock(); defer { lock.unlock() }
        return samples.count
    }

    func samples(from start: Int, count: Int) -> [Float] {
        lock.lock(); defer { lock.unlock() }
        return Self.slice(samples, start, count)
    }

    func level(from start: Int, seconds: Double, frequency: Double, rate: Double) -> Double {
        lock.lock(); let slice = Self.slice(samples, start, Int(seconds * rate)); lock.unlock()
        return SignalAnalysis.magnitude(at: frequency, in: slice, sampleRate: rate)
    }

    func windows(from start: Int, count: Int, seconds: Double, frequency: Double, rate: Double) -> [Double] {
        let n = Int(seconds * rate)
        return (0..<count).map { level(from: start + $0 * n, seconds: seconds, frequency: frequency, rate: rate) }
            .map { ($0 * 10_000).rounded() / 10_000 }
    }

    private static func slice(_ samples: [Float], _ start: Int, _ length: Int) -> [Float] {
        let lower = max(0, min(start, samples.count))
        let upper = max(lower, min(start + length, samples.count))
        return Array(samples[lower..<upper])
    }

    func stop() {
        guard let procID else { return }
        AudioDeviceStop(device, procID)
        AudioDeviceDestroyIOProcID(device, procID)
        self.procID = nil
    }
}

enum StepZeroSupport {
    /// Compiles and starts a separate process that taps `pid` (that process only, never a global tap) and reads it.
    static func launchTapper(pid: pid_t, behavior: String, clock: String) throws -> Process {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("resonance-step0-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = dir.appendingPathComponent("tapper.swift")
        let binary = dir.appendingPathComponent("tapper")
        try tapperSource.write(to: source, atomically: true, encoding: .utf8)
        let compile = Process()
        compile.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compile.arguments = ["swiftc", "-O", source.path, "-o", binary.path]
        try compile.run()
        compile.waitUntilExit()
        guard compile.terminationStatus == 0 else { throw CoreAudioError("compile tapper", compile.terminationStatus) }

        let tapper = Process()
        tapper.executableURL = binary
        tapper.arguments = [String(pid), behavior, clock]
        let pipe = Pipe()
        tapper.standardOutput = pipe
        try tapper.run()
        _ = try readLine(from: tapper, prefix: "READY", timeout: 10)
        return tapper
    }

    /// Reads the tapper's stdout until a line with `prefix` appears.
    static func readLine(from process: Process, prefix: String, timeout: Double) throws -> String {
        guard let pipe = process.standardOutput as? Pipe else { throw CoreAudioError("no pipe", -1) }
        let deadline = Date().addingTimeInterval(timeout)
        var seen = pending[process.processIdentifier] ?? ""
        while Date() < deadline {
            if let line = seen.split(separator: "\n").first(where: { $0.hasPrefix(prefix) }) {
                pending[process.processIdentifier] = seen.components(separatedBy: String(line)).dropFirst().joined()
                return String(line)
            }
            let data = pipe.fileHandleForReading.availableData
            if data.isEmpty { break }
            seen += String(decoding: data, as: UTF8.self)
        }
        throw CoreAudioError("tapper never printed \(prefix): \(seen)", -1)
    }

    nonisolated(unsafe) private static var pending: [pid_t: String] = [:]

    static let tapperSource = #"""
    import CoreAudio
    import Foundation

    // usage: tapper <pid> <muted|mutedWhenTapped> <clockUID|none>
    let args = CommandLine.arguments
    var pid = pid_t(args[1])!
    let behavior: CATapMuteBehavior = args[2] == "muted" ? .muted : .mutedWhenTapped
    let clock = args[3]

    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                                             mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMain)
    var process = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<pid_t>.size),
                               &pid, &size, &process)
    guard process != kAudioObjectUnknown else { print("NO PROCESS"); exit(2) }

    let description = CATapDescription(stereoMixdownOfProcesses: [process])
    description.uuid = UUID()
    description.isPrivate = true
    description.muteBehavior = behavior
    var tap = AudioObjectID(kAudioObjectUnknown)
    guard AudioHardwareCreateProcessTap(description, &tap) == noErr else { print("NO TAP"); exit(3) }

    var aggregate: [String: Any] = [
        kAudioAggregateDeviceNameKey: "Resonance Step0 Tapper",
        kAudioAggregateDeviceUIDKey: "resonance.step0.\(UUID().uuidString)",
        kAudioAggregateDeviceIsPrivateKey: true,
        kAudioAggregateDeviceTapAutoStartKey: true,
        kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                           kAudioSubTapDriftCompensationKey: true]],
    ]
    if clock != "none" {
        aggregate[kAudioAggregateDeviceMainSubDeviceKey] = clock
        aggregate[kAudioAggregateDeviceSubDeviceListKey] = [[kAudioSubDeviceUIDKey: clock]]
    }
    var device = AudioObjectID(kAudioObjectUnknown)
    guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device) == noErr else { print("NO AGGREGATE"); exit(4) }

    final class Meter: @unchecked Sendable {
        let lock = NSLock()
        var sum = 0.0
        var count = 0
    }
    let meter = Meter()
    var proc: AudioDeviceIOProcID?
    AudioDeviceCreateIOProcIDWithBlock(&proc, device, nil) { _, input, _, _, _ in
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let last = buffers.last, let data = last.mData else { return }
        let n = Int(last.mDataByteSize) / MemoryLayout<Float>.size
        let f = data.assumingMemoryBound(to: Float.self)
        var s = 0.0
        for i in 0..<n { s += Double(f[i] * f[i]) }
        meter.lock.lock(); meter.sum += s; meter.count += n; meter.lock.unlock()
    }
    guard AudioDeviceStart(device, proc) == noErr else { print("NO START"); exit(5) }
    print("READY")
    fflush(stdout)
    Thread.sleep(forTimeInterval: 1)
    meter.lock.lock()
    let rms = meter.count > 0 ? (meter.sum / Double(meter.count)).squareRoot() : 0
    let frames = meter.count
    meter.lock.unlock()
    print("RMS \(rms) samples \(frames)")
    fflush(stdout)
    Thread.sleep(forTimeInterval: 600) // until SIGKILL
    """#
}
