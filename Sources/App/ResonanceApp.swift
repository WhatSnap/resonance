import ResonanceCore
import SwiftUI

@main
struct ResonanceApp: App {
    @StateObject private var model = LiveEngine.makeModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
        } label: {
            Image(systemName: model.isEnabled ? "waveform.circle.fill" : "waveform.circle")
        }
        .menuBarExtraStyle(.window)
    }
}
