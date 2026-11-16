import AppKit
import ResonanceCore

/// Wires the real parts: Core Audio device provider → router → engine (system tap excluding Resonance, HAL output
/// on the current default output) → menu view model.
@MainActor
enum LiveEngine {
    static func makeModel() -> EngineViewModel {
        let provider = CoreAudioDeviceProvider()
        let scheduler = MainQueueScheduler()
        let router = DeviceRouter(provider: provider, scheduler: scheduler)
        let capture: CaptureSource
        if #available(macOS 14.4, *) {
            capture = TapCapture(target: .systemExcludingSelf)
        } else {
            capture = UnsupportedCapture()
        }
        let engine = ShiftEngine(capture: capture, output: HALOutput(), router: router, scheduler: scheduler)
        let model = EngineViewModel(engine: engine, onShutdown: { provider.invalidate() })
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                               queue: .main) { _ in
            MainActor.assumeIsolated { model.shutdown() }
        }
        return model
    }
}

/// Before macOS 14.4 there are no process taps.
@MainActor
final class UnsupportedCapture: CaptureSource {
    struct Unsupported: Error, LocalizedError {
        var errorDescription: String? { "Resonance needs macOS 14.4 or later." }
    }

    var isRunning: Bool { false }
    func prepare() throws -> Double { throw Unsupported() }
    func start(into buffer: DriftCompensatedBuffer) throws { throw Unsupported() }
    func stop() {}
    func rebuild() throws -> Double { throw Unsupported() }
    func currentSampleRate() -> Double? { nil }
    func currentHealth() -> CaptureHealth { CaptureHealth(signalSeen: false, silentSeconds: 0) }
}
