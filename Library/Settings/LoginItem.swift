import Foundation
import ServiceManagement

/// The system's "open at login" registration for this app. Wrapped so tests never touch the real service.
public protocol LoginItem: AnyObject {
    /// Whether the system has the app registered to open at login.
    var isRegistered: Bool { get }
    func register() throws
    func unregister() throws
}

/// `SMAppService.mainApp`: registers the running .app bundle itself. Needs a real bundle; never used by tests.
public final class MainAppLoginItem: LoginItem {
    public init() {}

    /// `.requiresApproval` counts as registered: the app asked, and the user still has to allow it in
    /// System Settings > General > Login Items. Turning the toggle off must still unregister it.
    public var isRegistered: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval: return true
        case .notRegistered, .notFound: return false
        @unknown default: return false
        }
    }

    public func register() throws { try SMAppService.mainApp.register() }
    public func unregister() throws { try SMAppService.mainApp.unregister() }
}

/// The "Open at login" toggle. Off on a fresh install: nothing registers until the user turns it on.
///
/// The system is the source of truth, not `UserDefaults`, so a removal in System Settings reads as off.
public final class OpenAtLogin {
    private let item: LoginItem

    public init(item: LoginItem = MainAppLoginItem()) {
        self.item = item
    }

    public var isOn: Bool { item.isRegistered }

    /// Registers or unregisters. Does nothing when the state already matches. Rethrows the system's error,
    /// so the view can put the switch back and say why.
    public func set(_ on: Bool) throws {
        guard on != item.isRegistered else { return }
        if on { try item.register() } else { try item.unregister() }
    }
}
