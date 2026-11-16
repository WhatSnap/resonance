import ResonanceCore
import SwiftUI

@main
struct ResonanceApp: App {
    @StateObject private var model = LiveEngine.makeModel()
    @StateObject private var openAtLogin = OpenAtLoginModel()

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
