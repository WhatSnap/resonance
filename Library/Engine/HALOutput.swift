import Atomics
import AudioToolbox
import CoreAudio
import Darwin

/// Plays the buffer on one device: AUHAL output unit ← NewTimePitch ← `DriftCompensatedBuffer.render`.
///
/// The client format is non-interleaved Float32 stereo at the buffer's rate; AUHAL converts to the device's rate.
/// Both render callbacks are C functions over a context allocated in `start`: no lock, no allocation, no Swift
/// runtime call beyond the buffer's own (checked by `scripts/check-realtime.sh`). Never touches the system default.
@MainActor
public final class HALOutput: OutputSink {
    public static let maxFramesPerSlice: UInt32 = 4096

    public private(set) var isRunning = false
    /// Starts since creation. For tests and diagnostics.
    public private(set) var startCount = 0
    private var outputUnit: AudioUnit?
    private var pitchUnit: AudioUnit?
    /// Retained for the render callbacks (`passRetained`) and released only after the unit is stopped, so a callback
    /// never sees a freed context even if the output is dropped without `stop()`.
    private var context: HALOutputContext?
    private var pastRenders = 0

    public init() {}

    /// Render callbacks run since creation.
    public var renderCount: Int { pastRenders + renderCountSinceStart }
    /// Render callbacks run since the last `start`.
    public var renderCountSinceStart: Int { context?.renders.load(ordering: .relaxed) ?? 0 }

    public func start(deviceID: DeviceID, clientSampleRate: Double, buffer: DriftCompensatedBuffer, pitchCents: Float) throws {
        stop()
        let context = HALOutputContext(buffer: buffer)
        self.context = context
        _ = Unmanaged.passRetained(context)
        do {
            try build(deviceID: deviceID, rate: clientSampleRate, pitchCents: pitchCents, context: context)
            guard let outputUnit else { throw CoreAudioError("AUHAL missing", kAudioUnitErr_Uninitialized) }
            try check(AudioOutputUnitStart(outputUnit), "AudioOutputUnitStart")
        } catch {
            teardown()
            throw error
        }
        startCount += 1
        isRunning = true
    }

    public func stop() {
        teardown()
    }

    public func setPitchCents(_ cents: Float) {
        guard let pitchUnit else { return }
        AudioUnitSetParameter(pitchUnit, kNewTimePitchParam_Pitch, kAudioUnitScope_Global, 0, cents, 0)
    }

    // MARK: Build and teardown

    private func build(deviceID: DeviceID, rate: Double, pitchCents: Float, context: HALOutputContext) throws {
        var format = AudioStreamBasicDescription(
            mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 2, mBitsPerChannel: 32,
            mReserved: 0)
        let formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var maxFrames = Self.maxFramesPerSlice
        let maxFramesSize = UInt32(MemoryLayout<UInt32>.size)

        // NewTimePitch, fed by the buffer.
        let pitch = try Self.instantiate(type: kAudioUnitType_FormatConverter, subType: kAudioUnitSubType_NewTimePitch)
        pitchUnit = pitch
        context.pitchUnit = pitch
        try check(AudioUnitSetProperty(pitch, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, formatSize),
                  "pitch input format")
        try check(AudioUnitSetProperty(pitch, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &format, formatSize),
                  "pitch output format")
        try check(AudioUnitSetProperty(pitch, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0,
                                       &maxFrames, maxFramesSize), "pitch max frames")
        var pitchInput = AURenderCallbackStruct(inputProc: halOutputPullBuffer,
                                                inputProcRefCon: Unmanaged.passUnretained(context).toOpaque())
        try check(AudioUnitSetProperty(pitch, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &pitchInput,
                                       UInt32(MemoryLayout<AURenderCallbackStruct>.size)), "pitch render callback")
        try check(AudioUnitSetParameter(pitch, kNewTimePitchParam_Pitch, kAudioUnitScope_Global, 0, pitchCents, 0), "set pitch")
        try check(AudioUnitInitialize(pitch), "AudioUnitInitialize(pitch)")

        // AUHAL on the device, output only, pulling from NewTimePitch.
        let output = try Self.instantiate(type: kAudioUnitType_Output, subType: kAudioUnitSubType_HALOutput)
        outputUnit = output
        var enable: UInt32 = 1
        var disable: UInt32 = 0
        try check(AudioUnitSetProperty(output, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &disable,
                                       UInt32(MemoryLayout<UInt32>.size)), "disable AUHAL input")
        try check(AudioUnitSetProperty(output, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &enable,
                                       UInt32(MemoryLayout<UInt32>.size)), "enable AUHAL output")
        var device = AudioDeviceID(deviceID)
        try check(AudioUnitSetProperty(output, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device,
                                       UInt32(MemoryLayout<AudioDeviceID>.size)), "bind output device \(deviceID)")
        try check(AudioUnitSetProperty(output, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, formatSize),
                  "AUHAL client format")
        try check(AudioUnitSetProperty(output, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0,
                                       &maxFrames, maxFramesSize), "AUHAL max frames")
        var outputInput = AURenderCallbackStruct(inputProc: halOutputPullPitch,
                                                 inputProcRefCon: Unmanaged.passUnretained(context).toOpaque())
        try check(AudioUnitSetProperty(output, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &outputInput,
                                       UInt32(MemoryLayout<AURenderCallbackStruct>.size)), "AUHAL render callback")
        try check(AudioUnitInitialize(output), "AudioUnitInitialize(AUHAL)")
    }

    private static func instantiate(type: OSType, subType: OSType) throws -> AudioUnit {
        var description = AudioComponentDescription(componentType: type, componentSubType: subType,
                                                    componentManufacturer: kAudioUnitManufacturer_Apple,
                                                    componentFlags: 0, componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw CoreAudioError("find audio unit", kAudioUnitErr_InvalidElement)
        }
        var unit: AudioUnit?
        try check(AudioComponentInstanceNew(component, &unit), "AudioComponentInstanceNew")
        guard let unit else { throw CoreAudioError("AudioComponentInstanceNew (nil)", kAudioUnitErr_Uninitialized) }
        return unit
    }

    private func teardown() {
        if let outputUnit {
            // Synchronous: no render callback runs after this returns.
            AudioOutputUnitStop(outputUnit)
            AudioUnitUninitialize(outputUnit)
            AudioComponentInstanceDispose(outputUnit)
        }
        if let pitchUnit {
            AudioUnitUninitialize(pitchUnit)
            AudioComponentInstanceDispose(pitchUnit)
        }
        outputUnit = nil
        pitchUnit = nil
        if let context {
            pastRenders += context.renders.load(ordering: .relaxed)
            Unmanaged.passUnretained(context).release()
        }
        context = nil
        isRunning = false
    }
}

/// State the render callbacks read. Allocated once per `start`, released after the unit stops.
final class HALOutputContext: @unchecked Sendable {
    let buffer: DriftCompensatedBuffer
    nonisolated(unsafe) var pitchUnit: AudioUnit?
    let renders = UnsafeAtomic<Int>.create(0)
    let secondsPerTick = HostClock.secondsPerTick
    /// On the first render after a start, frames above the target level are skipped (they piled up while the output
    /// was stopped), so a rebind does not add latency.
    let needsResync = UnsafeAtomic<Bool>.create(true)
    let discardL: UnsafeMutablePointer<Float>
    let discardR: UnsafeMutablePointer<Float>
    static let discardFrames = 1024

    init(buffer: DriftCompensatedBuffer) {
        self.buffer = buffer
        discardL = .allocate(capacity: Self.discardFrames)
        discardR = .allocate(capacity: Self.discardFrames)
        discardL.initialize(repeating: 0, count: Self.discardFrames)
        discardR.initialize(repeating: 0, count: Self.discardFrames)
    }

    deinit {
        discardL.deallocate()
        discardR.deallocate()
        renders.destroy()
        needsResync.destroy()
    }

    func now() -> Double { Double(mach_absolute_time()) * secondsPerTick }

    /// Consumer side of the buffer. Runs on the render thread.
    func pull(_ list: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        guard buffers.count >= 2, let l = buffers[0].mData, let r = buffers[1].mData else {
            for b in buffers { if let d = b.mData { memset(d, 0, Int(b.mDataByteSize)) } }
            return
        }
        let left = l.assumingMemoryBound(to: Float.self)
        let right = r.assumingMemoryBound(to: Float.self)
        let t = now()
        if needsResync.load(ordering: .relaxed) {
            needsResync.store(false, ordering: .relaxed)
            var excess = buffer.fillLevel - buffer.config.targetFillFrames
            while excess > 0 {
                let n = min(excess, Self.discardFrames)
                buffer.render(left: discardL, right: discardR, frameCount: n, hostTime: t)
                excess -= n
            }
        }
        buffer.render(left: left, right: right, frameCount: frames, hostTime: t)
        renders.wrappingIncrement(ordering: .relaxed)
    }
}

/// NewTimePitch's input: the buffer.
private func halOutputPullBuffer(_ refCon: UnsafeMutableRawPointer, _ flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                                 _ timeStamp: UnsafePointer<AudioTimeStamp>, _ bus: UInt32, _ frames: UInt32,
                                 _ data: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    guard let data else { return noErr }
    Unmanaged<HALOutputContext>.fromOpaque(refCon).takeUnretainedValue().pull(data, frames: Int(frames))
    return noErr
}

/// AUHAL's input: NewTimePitch.
private func halOutputPullPitch(_ refCon: UnsafeMutableRawPointer, _ flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                                _ timeStamp: UnsafePointer<AudioTimeStamp>, _ bus: UInt32, _ frames: UInt32,
                                _ data: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    let context = Unmanaged<HALOutputContext>.fromOpaque(refCon).takeUnretainedValue()
    guard let data, let pitch = context.pitchUnit else { return noErr }
    return AudioUnitRender(pitch, flags, timeStamp, 0, frames, data)
}
