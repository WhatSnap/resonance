import AppKit
import Foundation

/// When the controls window shows at launch (HQ-450). The app has no Dock icon, and its menu bar icon can hide
/// behind a MacBook notch, so a launch the user starts must show something. A launch at login stays quiet, except
/// the very first launch ever.
public struct LaunchWindowPolicy {
    public enum Key {
        public static let hasLaunched = "resonance.hasLaunched"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Call once per launch: it records that the app has launched.
    public func shouldShowAtLaunch(launchedAsLoginItem: Bool) -> Bool {
        let firstLaunch = !defaults.bool(forKey: Key.hasLaunched)
        defaults.set(true, forKey: Key.hasLaunched)
        return firstLaunch || !launchedAsLoginItem
    }

    /// True when macOS started the app as a login item. Valid only inside `applicationDidFinishLaunching`.
    public static func currentLaunchIsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}

/// Shows the controls window on launch and on every reopen (Finder, Spotlight, Dock), and keeps the app running in
/// the menu bar when that window closes. The window itself is built by the app and passed in as `showWindow`.
@MainActor
open class ResonanceAppDelegate: NSObject, NSApplicationDelegate {
    private let policy: LaunchWindowPolicy
    private let launchedAsLoginItem: () -> Bool
    private let showWindow: () -> Void

    public init(policy: LaunchWindowPolicy = LaunchWindowPolicy(),
                launchedAsLoginItem: @escaping () -> Bool = LaunchWindowPolicy.currentLaunchIsLoginItem,
                showWindow: @escaping () -> Void) {
        self.policy = policy
        self.launchedAsLoginItem = launchedAsLoginItem
        self.showWindow = showWindow
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        if policy.shouldShowAtLaunch(launchedAsLoginItem: launchedAsLoginItem()) {
            showWindow()
        }
    }

    /// Handled here, so AppKit adds nothing of its own.
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return false
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
