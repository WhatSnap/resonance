import CoreAudio
import Foundation
import Testing
@testable import ResonanceCore

/// Read-only Core Audio lookups. No tap, no IO, no prompt.
@Suite struct CoreAudioObjectsTests {
    @Test func defaultOutputDeviceIsReadableAndStable() throws {
        let first = try CoreAudioObjects.defaultOutputDevice()
        let second = try CoreAudioObjects.defaultOutputDevice()
        #expect(first != kAudioObjectUnknown)
        #expect(first == second)
        #expect(!(try CoreAudioObjects.uid(of: first)).isEmpty)
    }

    @Test func unknownUIDResolvesToNil() throws {
        #expect(try CoreAudioObjects.device(withUID: "resonance.no-such-device.\(UUID().uuidString)") == nil)
    }

    @Test func defaultOutputRoundTripsThroughItsUID() throws {
        let device = try CoreAudioObjects.defaultOutputDevice()
        let uid = try CoreAudioObjects.uid(of: device)
        #expect(try CoreAudioObjects.device(withUID: uid) == device)
    }

    @Test func coreAudioErrorNamesTheStatusCode() {
        let error = CoreAudioError("AudioDeviceStart", kAudioHardwareNotRunningError)
        #expect(error.description.contains("AudioDeviceStart"))
        #expect(error.description.contains("stop"))
    }
}
