import Combine

/// What the "Open at login" switch shows and does. Reads the system again on `refresh()`, so a removal made in
/// System Settings shows the next time the menu opens.
@MainActor
public final class OpenAtLoginModel: ObservableObject {
    @Published public private(set) var isOn: Bool
    @Published public private(set) var errorMessage: String?

    private let toggle: OpenAtLogin

    public init(toggle: OpenAtLogin = OpenAtLogin()) {
        self.toggle = toggle
        isOn = toggle.isOn
    }

    public func refresh() {
        isOn = toggle.isOn
    }

    /// On failure the switch goes back to what the system says, and the error shows under it.
    public func set(_ on: Bool) {
        do {
            try toggle.set(on)
            errorMessage = nil
        } catch {
            errorMessage = ShiftEngine.message(error)
        }
        isOn = toggle.isOn
    }
}
