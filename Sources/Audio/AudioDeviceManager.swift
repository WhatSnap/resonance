import Foundation
import AudioToolbox

final class AudioDevice: Sendable {
    let id: AudioObjectID
    let name: String
    let isInput: Bool
    let isOutput: Bool
    
    init(id: AudioObjectID, name: String, isInput: Bool, isOutput: Bool) {
        self.id = id
        self.name = name
        self.isInput = isInput
        self.isOutput = isOutput
    }
}

@MainActor
class AudioDeviceManager {
    static let shared = AudioDeviceManager()
    
    var devices: [AudioDevice] {
        return getAvailableDevices()
    }
    
    func getAvailableDevices() -> [AudioDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize)
        
        guard status == noErr else { return [] }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: deviceCount)
        
        let fetchStatus = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs)
        
        guard fetchStatus == noErr else { return [] }
        
        return deviceIDs.compactMap { id in
            let name = getDeviceName(id) ?? "Unknown Device"
            let isInput = getDeviceIsInput(id)
            let isOutput = getDeviceIsOutput(id)
            return AudioDevice(id: id, name: name, isInput: isInput, isOutput: isOutput)
        }
    }
    
    func findBlackHole() -> AudioDevice? {
        return devices.first { $0.name.lowercased().contains("blackhole") }
    }

    func getNominalSampleRate(_ id: AudioObjectID) -> Double? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var rate: Double = 0
        var size = UInt32(MemoryLayout<Double>.size)
        let status = AudioObjectGetPropertyData(id, &propertyAddress, 0, nil, &size, &rate)
        return status == noErr ? rate : nil
    }

    func getDefaultOutputDeviceID() -> AudioObjectID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dev: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &size, &dev)
        return status == noErr ? dev : nil
    }
    
    private func getDeviceName(_ id: AudioObjectID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        // AudioObjectGetPropertyData takes an UnsafeMutableRawPointer; use a raw byte buffer to avoid
        // forming an UnsafeMutableRawPointer directly to a Swift reference-typed variable.
        var name: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutableBytes(of: &name) { bytes in
            AudioObjectGetPropertyData(id, &propertyAddress, 0, nil, &size, bytes.baseAddress!)
        }
        
        return status == noErr ? (name as String?) : nil
    }
    
    private func getDeviceIsInput(_ id: AudioObjectID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(id, &propertyAddress, 0, nil, &size)
        return size > 0
    }
    
    private func getDeviceIsOutput(_ id: AudioObjectID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(id, &propertyAddress, 0, nil, &size)
        return size > 0
    }
}
