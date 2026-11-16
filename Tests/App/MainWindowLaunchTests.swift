import AppKit
import Foundation
import Testing
@testable import ResonanceCore

/// HQ-450: opening Resonance shows its controls in a window. Every test uses its own defaults suite, never `.standard`.
@MainActor
@Suite("Main window at launch and reopen")
struct MainWindowLaunchTests {
    static func isolatedDefaults() -> UserDefaults {
        let name = "resonance.tests.window.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    final class ShowCounter {
        var count = 0
    }

    static func delegate(defaults: UserDefaults, atLogin: Bool, counter: ShowCounter) -> ResonanceAppDelegate {
        ResonanceAppDelegate(policy: LaunchWindowPolicy(defaults: defaults),
                             launchedAsLoginItem: { atLogin },
                             showWindow: { counter.count += 1 })
    }

    static let launched = Notification(name: NSApplication.didFinishLaunchingNotification)

    // MARK: Launch-state logic

    @Test("first launch ever shows the window, even when started as a login item")
    func firstLaunchShows() {
        let policy = LaunchWindowPolicy(defaults: Self.isolatedDefaults())
        #expect(policy.shouldShowAtLaunch(launchedAsLoginItem: true))
    }

    @Test("a launch the user starts (Finder, Spotlight) shows the window every time")
    func userLaunchAlwaysShows() {
        let policy = LaunchWindowPolicy(defaults: Self.isolatedDefaults())
        #expect(policy.shouldShowAtLaunch(launchedAsLoginItem: false))
        #expect(policy.shouldShowAtLaunch(launchedAsLoginItem: false))
        #expect(policy.shouldShowAtLaunch(launchedAsLoginItem: false))
    }

    @Test("a later launch at login stays in the menu bar")
    func laterLoginLaunchStaysHidden() {
        let defaults = Self.isolatedDefaults()
        #expect(LaunchWindowPolicy(defaults: defaults).shouldShowAtLaunch(launchedAsLoginItem: false))
        // A new policy over the same suite is the next run of the app.
        #expect(!LaunchWindowPolicy(defaults: defaults).shouldShowAtLaunch(launchedAsLoginItem: true))
    }

    @Test("the first launch is remembered in the suite")
    func firstLaunchRecorded() {
        let defaults = Self.isolatedDefaults()
        #expect(defaults.object(forKey: LaunchWindowPolicy.Key.hasLaunched) == nil)
        _ = LaunchWindowPolicy(defaults: defaults).shouldShowAtLaunch(launchedAsLoginItem: true)
        #expect(defaults.bool(forKey: LaunchWindowPolicy.Key.hasLaunched))
    }

    // MARK: App delegate

    @Test("finishing a first launch requests the window once")
    func delegateShowsOnFirstLaunch() {
        let counter = ShowCounter()
        let delegate = Self.delegate(defaults: Self.isolatedDefaults(), atLogin: false, counter: counter)
        delegate.applicationDidFinishLaunching(Self.launched)
        #expect(counter.count == 1)
    }

    @Test("finishing a later login launch does not request the window")
    func delegateQuietAtLogin() {
        let defaults = Self.isolatedDefaults()
        _ = LaunchWindowPolicy(defaults: defaults).shouldShowAtLaunch(launchedAsLoginItem: false)
        let counter = ShowCounter()
        let delegate = Self.delegate(defaults: defaults, atLogin: true, counter: counter)
        delegate.applicationDidFinishLaunching(Self.launched)
        #expect(counter.count == 0)
    }

    @Test("opening the app again while it runs requests the window, with or without visible windows")
    func reopenShowsWindow() {
        let counter = ShowCounter()
        let delegate = Self.delegate(defaults: Self.isolatedDefaults(), atLogin: true, counter: counter)
        // The delegate handles the reopen itself, so AppKit does nothing more.
        #expect(delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false) == false)
        #expect(counter.count == 1)
        #expect(delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: true) == false)
        #expect(counter.count == 2)
    }

    @Test("closing the window does not quit the app")
    func closingWindowKeepsRunning() {
        let delegate = Self.delegate(defaults: Self.isolatedDefaults(), atLogin: false, counter: ShowCounter())
        #expect(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared) == false)
    }
}

/// HQ-451: SwiftUI's `@NSApplicationDelegateAdaptor` builds the delegate through Objective-C `alloc`/`init`, not
/// through a Swift initializer. A subclass in another module (the app's `AppDelegate`) must still get its own `init()`
/// that way, or the launch traps in the base class's unimplemented `init()`.
@MainActor
final class SubclassedAppDelegate: ResonanceAppDelegate {
    static var shows = 0

    override init() {
        super.init(policy: LaunchWindowPolicy(defaults: MainWindowLaunchTests.isolatedDefaults()),
                   launchedAsLoginItem: { false },
                   showWindow: { SubclassedAppDelegate.shows += 1 })
    }
}

@MainActor
@Suite("App delegate built the way SwiftUI builds it")
struct AppDelegateAdaptorTests {
    @Test("Objective-C init on a subclass runs the subclass's init, not a trap")
    func objcInitReachesSubclass() {
        let type: NSObject.Type = SubclassedAppDelegate.self
        let delegate = type.init() as? SubclassedAppDelegate
        #expect(delegate != nil)
        SubclassedAppDelegate.shows = 0
        delegate?.applicationDidFinishLaunching(MainWindowLaunchTests.launched)
        #expect(SubclassedAppDelegate.shows == 1)
    }
}
