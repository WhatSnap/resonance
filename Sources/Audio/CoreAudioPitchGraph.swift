import Foundation
import AudioToolbox
import AudioUnit

/// CoreAudio graph that captures audio from one device and renders to another,
/// applying the system NewTimePitch AudioUnit (pitch in cents).
final class CoreAudioPitchGraph {
    private var graph: AUGraph?
    private var timePitchNode = AUNode()
    private var outputNode = AUNode()
    private var inputUnit: AudioUnit?
    private var timePitchUnit: AudioUnit?
    private var outputUnit: AudioUnit?
    private var currentPitchCents: Float = 0

    // Ring buffer state (Deinterleaved)
    private let ringBufferCapacity: UInt32 = 16384 // frames
    private var leftRingBuffer: UnsafeMutablePointer<Float>?
    private var rightRingBuffer: UnsafeMutablePointer<Float>?
    private var writeIndex: UInt32 = 0
    private var readIndex: UInt32 = 0
    private var frameCount: UInt32 = 0
    private let ringBufferLock = NSLock()

    // Pre-allocated AudioBufferList for input rendering (2 channels, deinterleaved)
    private var inputABLPtr: UnsafeMutablePointer<AudioBufferList>?

    var isRunning: Bool = false

    deinit {
        stop()
        leftRingBuffer?.deallocate()
        rightRingBuffer?.deallocate()
        inputABLPtr?.deallocate()
    }

    func start(inputDeviceID: AudioObjectID, outputDeviceID: AudioObjectID, pitchCents: Float, sampleRate: Double) throws {
        stop()

        // 1. Initialize buffers
        if leftRingBuffer == nil {
            leftRingBuffer = UnsafeMutablePointer<Float>.allocate(capacity: Int(ringBufferCapacity))
            rightRingBuffer = UnsafeMutablePointer<Float>.allocate(capacity: Int(ringBufferCapacity))
        }
        
        // Allocate space for AudioBufferList + 1 additional AudioBuffer (total 2)
        if inputABLPtr == nil {
            let size = MemoryLayout<AudioBufferList>.size + MemoryLayout<AudioBuffer>.size
            let ptr = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<AudioBufferList>.alignment)
            inputABLPtr = ptr.assumingMemoryBound(to: AudioBufferList.self)
        }
        
        writeIndex = 0
        readIndex = 0
        frameCount = 0

        let asbd = Self.makeFloatNonInterleavedFormat(sampleRate: sampleRate)

        // 2. Setup Standalone Input Unit (BlackHole)
        var inputDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        
        guard let inputComponent = AudioComponentFindNext(nil, &inputDesc) else {
            throw CoreAudioPitchGraphError.audioUnitUnavailable
        }
        
        var iu: AudioUnit?
        try checkNoErr(AudioComponentInstanceNew(inputComponent, &iu), context: "AudioComponentInstanceNew(input)")
        self.inputUnit = iu
        guard let inputUnit = iu else { throw CoreAudioPitchGraphError.audioUnitUnavailable }

        var enable: UInt32 = 1
        var disable: UInt32 = 0
        try checkNoErr(AudioUnitSetProperty(inputUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enable, UInt32(MemoryLayout<UInt32>.size)), context: "Enable input scope")
        try checkNoErr(AudioUnitSetProperty(inputUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &disable, UInt32(MemoryLayout<UInt32>.size)), context: "Disable output scope")

        var inDev = inputDeviceID
        try checkNoErr(AudioUnitSetProperty(inputUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &inDev, UInt32(MemoryLayout<AudioObjectID>.size)), context: "bind input device")
        
        var format = asbd
        try checkNoErr(AudioUnitSetProperty(inputUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &format, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)), context: "set input unit format")
        
        var inputCallback = AURenderCallbackStruct(
            inputProc: { (inRefCon, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, ioData) -> OSStatus in
                let this = Unmanaged<CoreAudioPitchGraph>.fromOpaque(inRefCon).takeUnretainedValue()
                guard let iu = this.inputUnit, let ablPtr = this.inputABLPtr else { return noErr }
                
                this.ringBufferLock.lock()
                defer { this.ringBufferLock.unlock() }
                
                if this.frameCount + inNumberFrames > this.ringBufferCapacity {
                    return noErr // Overflow
                }
                
                let writeOffset = Int(this.writeIndex)
                let availableFramesToEnd = this.ringBufferCapacity - this.writeIndex
                
                // Set up the ABL buffers
                ablPtr.pointee.mNumberBuffers = 2
                let buffersPtr = UnsafeMutableRawPointer(ablPtr).advanced(by: MemoryLayout<UInt32>.size + MemoryLayout<UInt32>.size).assumingMemoryBound(to: AudioBuffer.self)
                
                if availableFramesToEnd >= inNumberFrames {
                    buffersPtr[0].mNumberChannels = 1
                    buffersPtr[0].mDataByteSize = inNumberFrames * 4
                    buffersPtr[0].mData = UnsafeMutableRawPointer(this.leftRingBuffer! + writeOffset)
                    
                    buffersPtr[1].mNumberChannels = 1
                    buffersPtr[1].mDataByteSize = inNumberFrames * 4
                    buffersPtr[1].mData = UnsafeMutableRawPointer(this.rightRingBuffer! + writeOffset)
                    
                    let status = AudioUnitRender(iu, ioActionFlags, inTimeStamp, 1, inNumberFrames, ablPtr)
                    if status == noErr {
                        this.writeIndex = (this.writeIndex + inNumberFrames) % this.ringBufferCapacity
                        this.frameCount += inNumberFrames
                    }
                    return status
                } else {
                    // Two-stage copy to handle wrap-around without real-time allocations
                    // We'll use a local stack-allocated buffer for temp storage if small enough,
                    // but since inNumberFrames is usually 512-1024, let's just use a fixed max size.
                    // Actually, we can just render twice with partial frame counts.
                    
                    let frames1 = availableFramesToEnd
                    buffersPtr[0].mNumberChannels = 1
                    buffersPtr[0].mDataByteSize = frames1 * 4
                    buffersPtr[0].mData = UnsafeMutableRawPointer(this.leftRingBuffer! + writeOffset)
                    buffersPtr[1].mNumberChannels = 1
                    buffersPtr[1].mDataByteSize = frames1 * 4
                    buffersPtr[1].mData = UnsafeMutableRawPointer(this.rightRingBuffer! + writeOffset)
                    
                    let status1 = AudioUnitRender(iu, ioActionFlags, inTimeStamp, 1, frames1, ablPtr)
                    if status1 != noErr { return status1 }
                    
                    let frames2 = inNumberFrames - frames1
                    buffersPtr[0].mNumberChannels = 1
                    buffersPtr[0].mDataByteSize = frames2 * 4
                    buffersPtr[0].mData = UnsafeMutableRawPointer(this.leftRingBuffer!)
                    buffersPtr[1].mNumberChannels = 1
                    buffersPtr[1].mDataByteSize = frames2 * 4
                    buffersPtr[1].mData = UnsafeMutableRawPointer(this.rightRingBuffer!)
                    
                    // Note: Technically the timestamp should be advanced for the second render call
                    var ts2 = inTimeStamp.pointee
                    ts2.mSampleTime += Float64(frames1)
                    
                    let status2 = withUnsafePointer(to: &ts2) { ts2Ptr in
                        AudioUnitRender(iu, ioActionFlags, ts2Ptr, 1, frames2, ablPtr)
                    }
                    if status2 == noErr {
                        this.writeIndex = frames2
                        this.frameCount += inNumberFrames
                    }
                    return status2
                }
            },
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        try checkNoErr(AudioUnitSetProperty(inputUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &inputCallback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)), context: "set input unit callback")
        
        try checkNoErr(AudioUnitInitialize(inputUnit), context: "AudioUnitInitialize(input)")

        // 3. Setup Output Graph (Pitch + AirPods)
        var g: AUGraph?
        try checkNoErr(NewAUGraph(&g), context: "NewAUGraph")
        guard let graph = g else { throw CoreAudioPitchGraphError.graphCreationFailed }
        self.graph = graph

        var timePitchDesc = AudioComponentDescription(
            componentType: kAudioUnitType_FormatConverter,
            componentSubType: kAudioUnitSubType_NewTimePitch,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        var outputDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        try checkNoErr(AUGraphAddNode(graph, &timePitchDesc, &timePitchNode), context: "AUGraphAddNode(timePitch)")
        try checkNoErr(AUGraphAddNode(graph, &outputDesc, &outputNode), context: "AUGraphAddNode(output)")

        try checkNoErr(AUGraphOpen(graph), context: "AUGraphOpen")

        var tu: AudioUnit?
        var ou: AudioUnit?
        try checkNoErr(AUGraphNodeInfo(graph, timePitchNode, nil, &tu), context: "AUGraphNodeInfo(timePitch)")
        try checkNoErr(AUGraphNodeInfo(graph, outputNode, nil, &ou), context: "AUGraphNodeInfo(output)")
        self.timePitchUnit = tu
        self.outputUnit = ou
        guard let timePitchUnit = tu, let outputUnit = ou else { throw CoreAudioPitchGraphError.audioUnitUnavailable }

        var outDev = outputDeviceID
        try checkNoErr(AudioUnitSetProperty(outputUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &outDev, UInt32(MemoryLayout<AudioObjectID>.size)), context: "bind output device")

        var tpFormat = asbd
        try checkNoErr(AudioUnitSetProperty(timePitchUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &tpFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)), context: "set pitch input format")
        try checkNoErr(AudioUnitSetProperty(timePitchUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &tpFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)), context: "set pitch output format")
        
        var ouFormat = asbd
        try checkNoErr(AudioUnitSetProperty(outputUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &ouFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)), context: "set output input format")

        try checkNoErr(AudioUnitSetParameter(timePitchUnit, kNewTimePitchParam_Pitch, kAudioUnitScope_Global, 0, pitchCents, 0), context: "set pitch")
        currentPitchCents = pitchCents

        try checkNoErr(AUGraphConnectNodeInput(graph, timePitchNode, 0, outputNode, 0), context: "connect pitch->output")

        var outputCallback = AURenderCallbackStruct(
            inputProc: { (inRefCon, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, ioData) -> OSStatus in
                let this = Unmanaged<CoreAudioPitchGraph>.fromOpaque(inRefCon).takeUnretainedValue()
                
                this.ringBufferLock.lock()
                defer { this.ringBufferLock.unlock() }
                
                let ablPtr = ioData!
                let buffersPtr = UnsafeMutableRawPointer(ablPtr).advanced(by: MemoryLayout<UInt32>.size + MemoryLayout<UInt32>.size).assumingMemoryBound(to: AudioBuffer.self)

                if this.frameCount < inNumberFrames {
                    for b in 0..<Int(ablPtr.pointee.mNumberBuffers) {
                        memset(buffersPtr[b].mData, 0, Int(inNumberFrames * 4))
                    }
                    return noErr
                }
                
                let readOffset = Int(this.readIndex)
                let availableFramesToEnd = this.ringBufferCapacity - this.readIndex
                
                let leftOut = buffersPtr[0].mData!.assumingMemoryBound(to: Float.self)
                let rightOut = buffersPtr[1].mData!.assumingMemoryBound(to: Float.self)
                
                if availableFramesToEnd >= inNumberFrames {
                    memcpy(leftOut, this.leftRingBuffer! + readOffset, Int(inNumberFrames * 4))
                    memcpy(rightOut, this.rightRingBuffer! + readOffset, Int(inNumberFrames * 4))
                    this.readIndex = (this.readIndex + inNumberFrames) % this.ringBufferCapacity
                } else {
                    let frames1 = availableFramesToEnd
                    let frames2 = inNumberFrames - frames1
                    
                    memcpy(leftOut, this.leftRingBuffer! + readOffset, Int(frames1 * 4))
                    memcpy(rightOut, this.rightRingBuffer! + readOffset, Int(frames1 * 4))
                    
                    memcpy(leftOut + Int(frames1), this.leftRingBuffer!, Int(frames2 * 4))
                    memcpy(rightOut + Int(frames1), this.rightRingBuffer!, Int(frames2 * 4))
                    
                    this.readIndex = frames2
                }
                
                this.frameCount -= inNumberFrames
                return noErr
            },
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        
        try checkNoErr(AUGraphSetNodeInputCallback(graph, timePitchNode, 0, &outputCallback), context: "SetNodeInputCallback")

        try checkNoErr(AUGraphInitialize(graph), context: "AUGraphInitialize")
        try checkNoErr(AudioOutputUnitStart(inputUnit), context: "AudioOutputUnitStart(input)")
        try checkNoErr(AUGraphStart(graph), context: "AUGraphStart")
        isRunning = true
    }

    func setPitchCents(_ pitchCents: Float) throws {
        guard let timePitchUnit else { return }
        try checkNoErr(
            AudioUnitSetParameter(timePitchUnit, kNewTimePitchParam_Pitch, kAudioUnitScope_Global, 0, pitchCents, 0),
            context: "set pitch"
        )
        currentPitchCents = pitchCents
    }

    func stop() {
        if let iu = inputUnit {
            _ = AudioOutputUnitStop(iu)
            AudioUnitUninitialize(iu)
            AudioComponentInstanceDispose(iu)
            inputUnit = nil
        }
        guard let graph else { 
            isRunning = false
            return 
        }
        _ = AUGraphStop(graph)
        _ = AUGraphUninitialize(graph)
        DisposeAUGraph(graph)
        self.graph = nil
        self.timePitchUnit = nil
        self.outputUnit = nil
        currentPitchCents = 0
        isRunning = false
    }

    private static func makeFloatNonInterleavedFormat(sampleRate: Double) -> AudioStreamBasicDescription {
        let channels: UInt32 = 2
        let bytesPerSample: UInt32 = 4
        
        return AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: bytesPerSample,
            mFramesPerPacket: 1,
            mBytesPerFrame: bytesPerSample,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 32,
            mReserved: 0
        )
    }
}

enum CoreAudioPitchGraphError: Error {
    case graphCreationFailed
    case audioUnitUnavailable
}

private let kNewTimePitchParam_Rate: AudioUnitParameterID = 0
private let kNewTimePitchParam_Pitch: AudioUnitParameterID = 1
private let kNewTimePitchParam_Overlap: AudioUnitParameterID = 2
private let kNewTimePitchParam_EnablePeakLocking: AudioUnitParameterID = 3

private func checkNoErr(_ status: OSStatus, context: String) throws {
    guard status == noErr else {
        throw AudioEngineError.coreAudio(status, context)
    }
}
