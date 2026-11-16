import Combine

/// What the menu shows and does: one switch, the pitch mode, a status line, and engine errors.
@MainActor
public final class EngineViewModel: ObservableObject {
    /// The switch. Off after a failed start; stays on through errors during device changes (the engine retries).
    @Published public private(set) var isEnabled = false
    @Published public private(set) var statusText = "Off"
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var notice: String?
    @Published public var pitchMode: PitchMode = .hz432 {
        didSet {
            engine.setPitchCents(pitchMode.pitchCents)
            settings?.pitchMode = pitchMode
        }
    }

    /// The status while the switch is on and the engine stopped on an error: it retries at the next device change.
    public static let interruptedStatus = "Interrupted, retrying at the next device change"

    private let engine: ShiftEngine
    /// Saves only what the user chose (the switch, the tuning). Engine pauses and quitting never write here.
    private let settings: SettingsStore?
    private var onShutdown: (() -> Void)?

    public init(engine: ShiftEngine, settings: SettingsStore? = nil, onShutdown: (() -> Void)? = nil) {
        self.engine = engine
        self.settings = settings
        self.onShutdown = onShutdown
        engine.setPitchCents(pitchMode.pitchCents)
        engine.onStateChange = { [weak self] state in self?.show(state) }
        engine.onNoticeChange = { [weak self] notice in self?.notice = notice }
        show(engine.state)
    }

    /// The user's switch. Saves the result, so the next launch comes back the same way.
    public func setEnabled(_ on: Bool) {
        apply(on)
        settings?.isEnabled = isEnabled
    }

    /// At launch: puts back the saved tuning and, if it was on, starts. Both values are read before anything is
    /// assigned. A failed start shows its error and leaves the saved state for the user's next action.
    public func restore() {
        guard let settings else { return }
        let wasEnabled = settings.isEnabled
        let savedMode = settings.pitchMode
        pitchMode = savedMode
        if wasEnabled { apply(true) }
    }

    private func apply(_ on: Bool) {
        if on {
            errorMessage = nil
            do {
                try engine.start()
                isEnabled = true
            } catch {
                isEnabled = false
            }
        } else {
            engine.stop()
            isEnabled = false
            errorMessage = nil
        }
        show(engine.state)
    }

    /// Stops the engine and runs the cleanup (listener removal) once. Call on quit.
    public func shutdown() {
        engine.stop()
        isEnabled = false
        onShutdown?()
        onShutdown = nil
    }

    private func show(_ state: EngineState) {
        switch state {
        case .off:
            statusText = "Off"
        case .running:
            statusText = "On"
            errorMessage = nil
        case .pausedHeadset:
            statusText = "Paused while the headset is in call mode"
        case .waitingForOutput:
            statusText = "Waiting for an output device"
        case .failed(let message):
            statusText = isEnabled ? Self.interruptedStatus : "Stopped"
            errorMessage = message
        }
    }
}
