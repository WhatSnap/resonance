import AudioToolbox
import CoreAudio
import Foundation
import Testing
@testable import ResonanceCore

extension BlackHoleSuites {
    /// HQ-429 spike: tap a child process that plays a sine, with that process muted.
    ///
    /// Off by default, because the first tap triggers the System Audio Recording prompt.
    /// Enabled with `RESONANCE_TAP_SPIKE=1`. Findings (JSON) go to `RESONANCE_TAP_SPIKE_OUT` when set.
    ///
    /// Silence: the child plays only to BlackHole 2ch (a virtual device), never to the default output.
    /// The aggregate is clocked by BlackHole, and its output buffers are never written. The test refuses to run
    /// while the Resonance app is open, because that app plays BlackHole's input on the speakers.
    @Suite(.enabled(if: ProcessInfo.processInfo.environment["RESONANCE_TAP_SPIKE"] == "1"), .serialized)
    struct ProcessTapSpikeTests {
        static let blackHoleUID = "BlackHole2ch_UID"
        static let toneHz = 997.0

        @Test func capturesMutedChildProcess() async throws {
            guard #available(macOS 14.4, *) else { return }
            let appRunning = try SpikeSupport.resonanceAppIsRunning()
            try #require(!appRunning, "Quit the Resonance app first: it plays BlackHole on the speakers.")
            let blackHoleLookup = try CoreAudioObjects.device(withUID: Self.blackHoleUID)
            let blackHole = try #require(blackHoleLookup, "BlackHole 2ch is required as a silent sink")

            let defaultBefore = try CoreAudioObjects.defaultOutputDevice()
            var findings = SpikeFindings()
            findings.defaultOutputBefore = try CoreAudioObjects.uid(of: defaultBefore)
            findings.blackHoleRate = try CoreAudioObjects.nominalSampleRate(of: blackHole)

            let child = try SpikeSupport.launchSineChild(deviceUID: Self.blackHoleUID, frequency: Self.toneHz, seconds: 60)
            defer { child.terminate(); child.waitUntilExit() }
            let processLookup = try await SpikeSupport.waitForProcessObject(pid: child.processIdentifier)
            let process = try #require(processLookup, "child never registered with Core Audio")

            // Reference: BlackHole's own loopback with no tap at all. This is what "audible" looks like.
            findings.loopbackNoTap = try await SpikeSupport.loopbackToneLevel(device: blackHole, frequency: Self.toneHz)

            for behavior in [CATapMuteBehavior.muted, .unmuted, .mutedWhenTapped] {
                let capture = ProcessTapCapture(configuration: .init(
                    processes: [process], muteBehavior: behavior, clockDeviceUID: Self.blackHoleUID, name: "Resonance Spike"))
                var run = SpikeRun(behavior: SpikeFindings.name(behavior))

                if behavior == .mutedWhenTapped {
                    // Tap exists, IO not started: is the child muted yet?
                    try capture.create()
                    run.loopbackTapCreatedIdle = try await SpikeSupport.loopbackToneLevel(device: blackHole, frequency: Self.toneHz)
                }

                let recorder = SpikeRecorder()
                try capture.start(queue: DispatchQueue(label: "spike.tap", qos: .userInitiated)) { list, _ in
                    recorder.append(list)
                }
                let applied = try capture.appliedMuteBehavior()
                #expect(applied == behavior, "the tap reports the mute behavior it was given")
                let rate = try CoreAudioObjects.nominalSampleRate(of: capture.aggregateID)
                run.aggregateRate = rate
                run.tapFormatRate = capture.tapFormat?.mSampleRate ?? 0
                run.bufferLayout = try CoreAudioObjects.bufferChannelCounts(of: capture.aggregateID, scope: kAudioObjectPropertyScopeInput)
                run.tapBuffers = Array(capture.tapBufferRange)

                try await Task.sleep(for: .seconds(2))
                let snapshot = recorder.drain()
                let tap = snapshot.mono(buffers: capture.tapBufferRange)
                let loopback = snapshot.mono(buffers: capture.clockBufferRange)
                run.tapRMS = SignalAnalysis.rms(tap)
                run.tapPeakHz = SignalAnalysis.peakFrequency(tap, sampleRate: rate) ?? 0
                run.loopbackWhileTapped = SignalAnalysis.magnitude(at: Self.toneHz, in: loopback, sampleRate: rate)

                #expect(run.tapRMS > 0, "captured audio has RMS above 0 (\(run.behavior))")
                #expect(abs(run.tapPeakHz - Self.toneHz) <= 1, "FFT peak \(run.tapPeakHz) Hz within 1 Hz (\(run.behavior))")

                if behavior == .muted {
                    // Recovery path: full teardown and rebuild, then capture again.
                    try capture.rebuild()
                    try await Task.sleep(for: .seconds(1))
                    let rebuilt = recorder.drain().mono(buffers: capture.tapBufferRange)
                    run.rmsAfterRebuild = SignalAnalysis.rms(rebuilt)
                    #expect(run.rmsAfterRebuild > 0, "capture works again after a rebuild")
                }
                capture.stop()
                findings.runs.append(run)
            }

            // The muted tap really silences the child: its loopback tone drops far below the unmuted level.
            let muted = try #require(findings.runs.first { $0.behavior == "muted" })
            let unmuted = try #require(findings.runs.first { $0.behavior == "unmuted" })
            #expect(unmuted.loopbackWhileTapped > 0.05, "unmuted: the child is heard on its device")
            #expect(muted.loopbackWhileTapped < unmuted.loopbackWhileTapped * 0.1, "muted: the child is silenced on its device")

            let defaultAfter = try CoreAudioObjects.defaultOutputDevice()
            findings.defaultOutputAfter = try CoreAudioObjects.uid(of: defaultAfter)
            #expect(defaultAfter == defaultBefore, "system default output unchanged")

            try findings.write()
        }
    }
}

// MARK: - Support

struct SpikeRun: Codable {
    var behavior: String
    var aggregateRate = 0.0
    var tapFormatRate = 0.0
    var bufferLayout: [Int] = []
    var tapBuffers: [Int] = []
    var tapRMS: Float = 0
    var tapPeakHz = 0.0
    var loopbackWhileTapped = 0.0
    var loopbackTapCreatedIdle: Double?
    var rmsAfterRebuild: Float = 0
}

struct SpikeFindings: Codable {
    var defaultOutputBefore = ""
    var defaultOutputAfter = ""
    var blackHoleRate = 0.0
    var loopbackNoTap = 0.0
    var runs: [SpikeRun] = []

    @available(macOS 14.2, *)
    static func name(_ behavior: CATapMuteBehavior) -> String {
        switch behavior {
        case .unmuted: "unmuted"
        case .muted: "muted"
        case .mutedWhenTapped: "mutedWhenTapped"
        @unknown default: "unknown(\(behavior.rawValue))"
        }
    }

    func write() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        print("TAP-SPIKE-FINDINGS", String(decoding: data, as: UTF8.self))
        if let path = ProcessInfo.processInfo.environment["RESONANCE_TAP_SPIKE_OUT"] {
            try data.write(to: URL(fileURLWithPath: path))
        }
    }
}

/// Copies every input buffer of each IO cycle, per buffer index. Lock-protected; fine for a test.
final class SpikeRecorder: @unchecked Sendable {
    struct Snapshot {
        var buffers: [Int: (channels: Int, samples: [Float])] = [:]

        /// First channel of each listed buffer, concatenated per buffer and summed across buffers.
        func mono(buffers indices: Range<Int>) -> [Float] {
            var result: [Float] = []
            for index in indices {
                guard let buffer = buffers[index] else { continue }
                let channel = SignalAnalysis.channel(0, of: buffer.samples, channels: max(buffer.channels, 1))
                if result.isEmpty { result = channel } else {
                    for i in 0..<min(result.count, channel.count) { result[i] += channel[i] }
                }
            }
            return result
        }
    }

    private let lock = NSLock()
    private var snapshot = Snapshot()

    func append(_ list: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        lock.lock(); defer { lock.unlock() }
        for (index, buffer) in buffers.enumerated() {
            guard let data = buffer.mData else { continue }
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let samples = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count)
            snapshot.buffers[index, default: (Int(buffer.mNumberChannels), [])].samples.append(contentsOf: samples)
        }
    }

    func drain() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        let result = snapshot
        snapshot = Snapshot()
        return result
    }
}

enum SpikeSupport {
    static func resonanceAppIsRunning() throws -> Bool {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-axo", "comm="]
        let pipe = Pipe()
        ps.standardOutput = pipe
        try ps.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        ps.waitUntilExit()
        return output.split(separator: "\n").contains { $0.hasSuffix("/Resonance") || $0 == "Resonance" }
    }

    /// Compiles and starts a child that plays a sine on one device by UID (never the default output).
    static func launchSineChild(deviceUID: String, frequency: Double, seconds: Double) throws -> Process {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("resonance-tap-spike-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = dir.appendingPathComponent("sine_child.swift")
        let binary = dir.appendingPathComponent("sine_child")
        try sineChildSource.write(to: source, atomically: true, encoding: .utf8)

        let compile = Process()
        compile.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compile.arguments = ["swiftc", "-O", source.path, "-o", binary.path]
        try compile.run()
        compile.waitUntilExit()
        guard compile.terminationStatus == 0 else { throw CoreAudioError("compile sine child", compile.terminationStatus) }

        let child = Process()
        child.executableURL = binary
        child.arguments = [deviceUID, String(frequency), String(seconds)]
        let pipe = Pipe()
        child.standardOutput = pipe
        try child.run()
        // Wait for READY: IO has started on the device.
        let deadline = Date().addingTimeInterval(10)
        var seen = ""
        while Date() < deadline, !seen.contains("READY") {
            let data = pipe.fileHandleForReading.availableData
            if data.isEmpty { break }
            seen += String(decoding: data, as: UTF8.self)
        }
        guard seen.contains("READY") else {
            child.terminate()
            throw CoreAudioError("sine child did not start: \(seen)", -1)
        }
        return child
    }

    static func waitForProcessObject(pid: pid_t) async throws -> AudioObjectID? {
        for _ in 0..<30 {
            if let object = try CoreAudioObjects.processObject(pid: pid) { return object }
            try await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    /// Reads the device's input (BlackHole loops its output to its input) for one second and returns the level
    /// of the tone. A plain IOProc on the device; nothing is written to its output.
    static func loopbackToneLevel(device: AudioDeviceID, frequency: Double) async throws -> Double {
        let recorder = SpikeRecorder()
        var procID: AudioDeviceIOProcID?
        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, device, DispatchQueue(label: "spike.loopback")) { _, input, _, _, _ in
            recorder.append(input)
        }, "loopback IOProc")
        defer { AudioDeviceDestroyIOProcID(device, procID!) }
        try check(AudioDeviceStart(device, procID), "loopback start")
        try await Task.sleep(for: .seconds(1))
        AudioDeviceStop(device, procID)
        let rate = try CoreAudioObjects.nominalSampleRate(of: device)
        let samples = recorder.drain().mono(buffers: 0..<8)
        return SignalAnalysis.magnitude(at: frequency, in: samples, sampleRate: rate)
    }

    static let sineChildSource = #"""
    import CoreAudio
    import Foundation

    // usage: sine_child <deviceUID> <hz> <seconds>
    let args = CommandLine.arguments
    let uid = args[1] as CFString
    let hz = Double(args[2])!
    let seconds = Double(args[3])!

    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
                                             mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMain)
    var cfUID = uid
    var device = AudioDeviceID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    _ = withUnsafeMutablePointer(to: &cfUID) {
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                   UInt32(MemoryLayout<CFString>.size), $0, &size, &device)
    }
    guard device != kAudioObjectUnknown else { print("NO DEVICE"); exit(2) }

    var rateAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
    var rate = Float64(0)
    size = UInt32(MemoryLayout<Float64>.size)
    AudioObjectGetPropertyData(device, &rateAddress, 0, nil, &size, &rate)

    final class Phase: @unchecked Sendable { var value = 0.0 }
    let phase = Phase()
    let step = 2 * Double.pi * hz / rate
    var proc: AudioDeviceIOProcID?
    AudioDeviceCreateIOProcIDWithBlock(&proc, device, nil) { _, _, _, output, _ in
        let buffers = UnsafeMutableAudioBufferListPointer(output)
        let channels = Int(buffers.first?.mNumberChannels ?? 1)
        let frames = Int(buffers.first?.mDataByteSize ?? 0) / MemoryLayout<Float>.size / max(channels, 1)
        var p = phase.value
        for frame in 0..<frames {
            let sample = Float(0.25 * sin(p))
            p += step
            for buffer in buffers {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let ch = Int(buffer.mNumberChannels)
                for c in 0..<ch { data[frame * ch + c] = sample }
            }
        }
        phase.value = p.truncatingRemainder(dividingBy: 2 * Double.pi)
    }
    AudioDeviceStart(device, proc)
    print("READY")
    fflush(stdout)
    Thread.sleep(forTimeInterval: seconds)
    AudioDeviceStop(device, proc)
    """#
}
