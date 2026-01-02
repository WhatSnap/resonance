import Foundation
import AVFoundation
import Combine
import AudioToolbox

@MainActor
class AudioEngine: ObservableObject {
    enum PitchMode: String, CaseIterable, Identifiable {
        case off
        case hz432
        case demo
        
        var id: String { rawValue }
        
        var title: String {
            switch self {
            case .off: return "Off (440)"
            case .hz432: return "432Hz"
            case .demo: return "Demo"
            }
        }
        
        /// Cents to apply via NewTimePitch.
        var pitchCents: Float {
            switch self {
            case .off: return 0
            case .hz432: return Constants.Audio.centsShift
            case .demo: return -100 // 1 semitone down (obvious A/B)
            }
        }
    }
    
    @Published var isEnabled = false
    @Published var isStarting = false
    @Published var selectedDeviceID: AudioObjectID = 0
    @Published var availableDevices: [AudioDevice] = []
    @Published var blackHoleAvailable = false
    @Published var pitchMode: PitchMode = .hz432
    
    /// Tracks if we've already tried to show the setup wizard this session.
    var hasAttemptedAutoSetup = false
    
    private let graph = CoreAudioPitchGraph()
    
    var onProcess: (([Float]) -> [Float])?
    
    init() {
        refreshDevices()
        setupNotification()
    }
    
    func refreshDevices() {
        let allDevices = AudioDeviceManager.shared.getAvailableDevices()
        // Exclude BlackHole itself (used as input) and Multi-Output devices (feedback risk / not usable as a target).
        self.availableDevices = allDevices.filter {
            guard $0.isOutput else { return false }
            let name = $0.name.lowercased()
            if name.contains("blackhole") { return false }
            if name.contains("multi-output") { return false }
            return true
        }
        
        self.blackHoleAvailable = allDevices.contains { $0.name.lowercased().contains("blackhole") }
        
        // If selection is unset or stale, pick the first available output device.
        if selectedDeviceID == 0 || !availableDevices.contains(where: { $0.id == selectedDeviceID }) {
            selectedDeviceID = availableDevices.first?.id ?? 0
        }
    }
    
    private func setupNotification() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        // IMPORTANT:
        // CoreAudio invokes device-change callbacks on an internal HAL queue, not the main thread.
        // Because this type is @MainActor, a listener created in this context can crash with a
        // libdispatch "expected to execute on main-thread" assertion when invoked off-main.
        // Use the block-based API and explicitly deliver on DispatchQueue.main.
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self = self else { return }
            self.refreshDevices()
            
            // If the engine is running, we might need to restart it to re-bind hardware.
            if self.isEnabled && !self.isStarting {
                Task { @MainActor in
                    do {
                        try self.start()
                    } catch {
                        print("Auto-restart failed after hardware change: \(error)")
                    }
                }
            }
        }

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            block
        )
    }
    
    func start() throws {
        // If we're already running, treat "start" as "restart" so we can re-bind devices
        // (e.g. user changes output in the picker, or changes Audio MIDI configuration).
        if isEnabled {
            stop()
        }
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        
        guard let blackHole = AudioDeviceManager.shared.findBlackHole() else {
            throw AudioEngineError.blackHoleNotFound
        }
        
        guard let outputDevice = availableDevices.first(where: { $0.id == selectedDeviceID }) else {
            throw AudioEngineError.outputDeviceNotFound
        }
        
        try start(inputDevice: blackHole, outputDevice: outputDevice)
        isEnabled = true
    }
    
    func start(inputDevice: AudioDevice, outputDevice: AudioDevice) throws {
        let inputID = inputDevice.id
        let outputID = outputDevice.id

        // Prefer output device nominal sample rate; AUHAL will perform conversion if needed.
        let sr = AudioDeviceManager.shared.getNominalSampleRate(outputID) ?? 48_000.0
        try graph.start(
            inputDeviceID: inputID,
            outputDeviceID: outputID,
            pitchCents: pitchMode.pitchCents,
            sampleRate: sr
        )
    }

    func applyPitchMode() throws {
        // If engine isn't running yet, just store the preference; it'll be applied at start().
        guard isEnabled else { return }
        try graph.setPitchCents(pitchMode.pitchCents)
    }

    func stop() {
        graph.stop()
        isEnabled = false
    }
}

enum AudioEngineError: LocalizedError {
    case blackHoleNotFound
    case outputDeviceNotFound
    case coreAudio(OSStatus, String)
    
    var errorDescription: String? {
        switch self {
        case .blackHoleNotFound: return "BlackHole audio driver not found."
        case .outputDeviceNotFound: return "Selected output device not found."
        case .coreAudio(let status, let context): return "CoreAudio error \(status) (\(context))."
        }
    }
}

private func checkNoErr(_ status: OSStatus, context: String) throws {
    guard status == noErr else {
        throw AudioEngineError.coreAudio(status, context)
    }
}
