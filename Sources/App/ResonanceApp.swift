import SwiftUI

@main
struct ResonanceApp: App {
    @StateObject private var audioEngine = AudioEngine()
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(audioEngine)
        } label: {
            Image(systemName: audioEngine.isEnabled ? "waveform.circle.fill" : "waveform.circle")
        }
        .menuBarExtraStyle(.window)
        
        Settings {
            PreferencesView()
                .environmentObject(audioEngine)
        }
        
        Window("Resonance Setup", id: "setup") {
            SetupView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
