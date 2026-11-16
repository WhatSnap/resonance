import AppKit

/// Shows the controls window and keeps it reachable (HQ-457).
///
/// While the window is open the app is `.regular`: it has a Dock icon and a place in Command-Tab. When the window
/// closes the app goes back to `.accessory` and lives in the menu bar only. As an accessory app the window got lost:
/// the System Audio Recording dialog took the front when the switch started the engine, and afterwards macOS brought
/// the next regular app forward, leaving Resonance's open window behind everything with no way back to it.
///
/// The window is built once and only hidden by its close button, so reopening shows the same window.
@MainActor
public final class MainWindowPresenter: NSObject, NSWindowDelegate {
    private let makeWindow: @MainActor () -> NSWindow
    private let setPolicy: @MainActor (NSApplication.ActivationPolicy) -> Void
    private let activate: @MainActor () -> Void
    private let order: @MainActor (NSWindow) -> Void

    public private(set) var window: NSWindow?
    /// True from `show()` until the window closes.
    public private(set) var isOpen = false

    /// The defaults are the real app's. Tests pass closures that record instead of touching `NSApp` or the screen.
    public init(makeWindow: @escaping @MainActor () -> NSWindow,
                setPolicy: @escaping @MainActor (NSApplication.ActivationPolicy) -> Void = { _ = NSApp.setActivationPolicy($0) },
                activate: @escaping @MainActor () -> Void = { NSApp.activate() },
                order: @escaping @MainActor (NSWindow) -> Void = { $0.makeKeyAndOrderFront(nil) }) {
        self.makeWindow = makeWindow
        self.setPolicy = setPolicy
        self.activate = activate
        self.order = order
        super.init()
    }

    public func show() {
        let window = self.window ?? prepare(makeWindow())
        self.window = window
        isOpen = true
        setPolicy(.regular)
        activate()
        order(window)
    }

    public func windowWillClose(_ notification: Notification) {
        guard isOpen else { return }
        isOpen = false
        setPolicy(.accessory)
    }

    private func prepare(_ window: NSWindow) -> NSWindow {
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.delegate = self
        return window
    }
}
