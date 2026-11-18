import CoreAudio
import Foundation

/// A Core Audio call that returned an error status.
public struct CoreAudioError: Error, CustomStringConvertible, Equatable {
    public let operation: String
    public let status: OSStatus

    public init(_ operation: String, _ status: OSStatus) {
        self.operation = operation
        self.status = status
    }

    public var description: String { "\(operation) failed with OSStatus \(status) (\(fourCC(status)))" }
}

private func fourCC(_ status: OSStatus) -> String {
    let value = UInt32(bitPattern: status)
    let bytes = [24, 16, 8, 0].map { UInt8((value >> UInt32($0)) & 0xFF) }
    guard bytes.allSatisfy({ $0 >= 32 && $0 < 127 }) else { return "\(status)" }
    return String(bytes: bytes, encoding: .ascii) ?? "\(status)"
}

@inline(__always)
func check(_ status: OSStatus, _ operation: @autoclosure () -> String) throws {
    guard status == noErr else { throw CoreAudioError(operation(), status) }
}

/// Read-only lookups on the Core Audio object graph. Nothing here changes system state.
public enum CoreAudioObjects {
    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, initial: T) throws -> T {
        var address = address(selector, scope: scope)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value), "read \(fourCC(OSStatus(bitPattern: selector)))")
        return value
    }

    static func readString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value), "read string")
        guard let value else { throw CoreAudioError("read string (nil)", kAudioHardwareUnknownPropertyError) }
        return value.takeRetainedValue() as String
    }

    /// The system default output device.
    public static func defaultOutputDevice() throws -> AudioDeviceID {
        try read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice,
                 initial: AudioDeviceID(kAudioObjectUnknown))
    }

    public static func uid(of device: AudioObjectID) throws -> String {
        try readString(device, kAudioDevicePropertyDeviceUID)
    }

    public static func name(of device: AudioObjectID) throws -> String {
        try readString(device, kAudioObjectPropertyName)
    }

    /// The device with this UID, or nil when it is not present.
    public static func device(withUID uid: String) throws -> AudioDeviceID? {
        var address = address(kAudioHardwarePropertyTranslateUIDToDevice)
        var cfUID = uid as CFString
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { uidPointer in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                       UInt32(MemoryLayout<CFString>.size), uidPointer, &size, &device)
        }
        try check(status, "translate UID \(uid)")
        return device == kAudioObjectUnknown ? nil : device
    }

    /// The Core Audio process object for a PID, or nil while the process has no audio client.
    public static func processObject(pid: pid_t) throws -> AudioObjectID? {
        var address = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var pid = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                             UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object),
                  "translate PID \(pid)")
        return object == kAudioObjectUnknown ? nil : object
    }

    public static func nominalSampleRate(of device: AudioObjectID) throws -> Double {
        try read(device, kAudioDevicePropertyNominalSampleRate, initial: Float64(0))
    }

    /// Channel count of each buffer the device presents in a scope, in IOProc buffer order.
    public static func bufferChannelCounts(of device: AudioObjectID, scope: AudioObjectPropertyScope) throws -> [Int] {
        var address = address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size), "stream configuration size")
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        try check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw), "stream configuration")
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.map { Int($0.mNumberChannels) }
    }
}
