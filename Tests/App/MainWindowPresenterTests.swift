import AppKit
import Foundation
import Testing
@testable import ResonanceCore

/// HQ-457: the controls window keeps a Dock icon while it is open, so it can always be found again.
///
/// Root cause of "the window closed when I pressed a switch" (2026-11-16, unified log): turning the switch on started
/// the engine, the engine's tap asked for the System Audio Recording permission, and macOS put its dialog in front.
/// When the dialog went away, macOS brought the next regular app to the front (WhatsApp). Resonance was an accessory
/// app, with no Dock icon and no place in Command-Tab, so its window stayed open behind every other window, out of
/// reach. The window never closed. While it is open, Resonance is now a regular app.
///
/// No test puts a window on screen: `order` records instead of calling `makeKeyAndOrderFront`.
@MainActor
@Suite("Controls window and activation policy")
struct MainWindowPresenterTests {
    final class Recorder {
        var policies: [NSApplication.ActivationPolicy] = []
        var activations = 0
        var orders = 0
        var windowsMade = 0
    }

    static func presenter(_ recorder: Recorder) -> MainWindowPresenter {
        MainWindowPresenter(
            makeWindow: {
                recorder.windowsMade += 1
                return NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                styleMask: [.titled, .closable], backing: .buffered, defer: true)
            },
            setPolicy: { recorder.policies.append($0) },
            activate: { recorder.activations += 1 },
            order: { _ in recorder.orders += 1 })
    }

    @Test("showing the window makes the app regular (Dock icon) before activating it")
    func showMakesRegular() {
        let recorder = Recorder()
        let presenter = Self.presenter(recorder)
        presenter.show()
        #expect(recorder.policies == [.regular])
        #expect(recorder.activations == 1)
        #expect(recorder.orders == 1)
        #expect(presenter.isOpen)
    }

    @Test("closing the window puts the app back in the menu bar only (accessory)")
    func closeMakesAccessory() {
        let recorder = Recorder()
        let presenter = Self.presenter(recorder)
        presenter.show()
        presenter.window?.close()
        #expect(recorder.policies == [.regular, .accessory])
        #expect(!presenter.isOpen)
    }

    @Test("the window is built once, survives a close, and shows again as regular")
    func reopenReusesWindow() {
        let recorder = Recorder()
        let presenter = Self.presenter(recorder)
        presenter.show()
        let first = presenter.window
        presenter.window?.close()
        presenter.show()
        #expect(recorder.windowsMade == 1)
        #expect(presenter.window === first)
        #expect(recorder.policies == [.regular, .accessory, .regular])
        #expect(presenter.isOpen)
    }

    @Test("losing focus to another app (the permission dialog) does not close or hide the window")
    func deactivationKeepsWindow() {
        let recorder = Recorder()
        let presenter = Self.presenter(recorder)
        presenter.show()
        #expect(presenter.window?.isReleasedWhenClosed == false)
        #expect(presenter.window?.hidesOnDeactivate == false)
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApplication.shared)
        #expect(presenter.isOpen)
        #expect(recorder.policies == [.regular])
    }

    @Test("a launch the user starts shows the window as regular, also after the first launch")
    func launchAfterFirstShowsRegular() {
        let name = "resonance.tests.presenter.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(true, forKey: LaunchWindowPolicy.Key.hasLaunched)

        let recorder = Recorder()
        let presenter = Self.presenter(recorder)
        let delegate = ResonanceAppDelegate(policy: LaunchWindowPolicy(defaults: defaults),
                                            launchedAsLoginItem: { false },
                                            showWindow: { presenter.show() })
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        #expect(presenter.isOpen)
        #expect(recorder.policies == [.regular])
    }
}
