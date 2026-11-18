import ResonanceCore
import SwiftUI

@main
struct ResonanceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppParts.model
    @StateObject private var openAtLogin = AppParts.openAtLogin

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
                .environmentObject(openAtLogin)
        } label: {
            Image(systemName: model.isEnabled ? "waveform.circle.fill" : "waveform.circle")
        }
        .menuBarExtraStyle(.window)
    }
}
