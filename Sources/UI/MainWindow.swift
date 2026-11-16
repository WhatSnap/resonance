import AppKit
import ResonanceCore
import SwiftUI

/// The one view model and login switch, shared by the menu bar popover and the controls window (HQ-450).
@MainActor
enum AppParts {
    static let model = LiveEngine.makeModel()
    static let openAtLogin = OpenAtLoginModel()
}

/// The controls window: the menu's own view, plus where to find the menu bar icon after closing it.
struct MainWindowView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuBarView()
            Divider()
            Label("Resonance keeps running after you close this window. Its controls stay in the menu bar, under the "
                  + "waveform icon at the top right of the screen. On a Mac with a notch, the icon can hide behind "
                  + "other icons.", systemImage: "waveform.circle")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding()
                .frame(width: 280, alignment: .leading)
        }
        .environmentObject(AppParts.model)
        .environmentObject(AppParts.openAtLogin)
    }
}

/// Builds the window once and brings it to the front each time it is asked for. Closing only hides it.
@MainActor
final class MainWindowController {
    static let shared = MainWindowController()

    private var window: NSWindow?

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Resonance"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MainWindowView())
        window.setContentSize(window.contentView?.fittingSize ?? NSSize(width: 280, height: 300))
        window.center()
        return window
    }
}

/// The app's delegate: the tested launch and reopen rules, showing the window above.
@MainActor
final class AppDelegate: ResonanceAppDelegate {
    override init() {
        super.init(showWindow: { MainWindowController.shared.show() })
    }
}
