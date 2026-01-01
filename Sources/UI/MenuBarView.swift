import SwiftUI
import AudioToolbox

struct MenuBarView: View {
    @EnvironmentObject var audioEngine: AudioEngine
    @Environment(\.openWindow) var openWindow
    @AppStorage("setupComplete") private var setupComplete = false
    @State private var showStartError = false
    @State private var startErrorMessage = ""
    
    var body: some View {
        VStack(spacing: 12) {
            // Status header
            HStack {
                Circle()
                    .fill(audioEngine.isEnabled ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                
                Text(audioEngine.isEnabled ? "Resonance Active" : "Resonance Inactive")
                    .font(.headline)
                
                Spacer()
                
                Button(audioEngine.isEnabled ? "Disable" : "Enable") {
                    toggleAudio()
                }
                .buttonStyle(.borderedProminent)
                .tint(audioEngine.isEnabled ? .gray : .accentColor)
                .disabled(audioEngine.isStarting)
            }
            
            Divider()
            
            // Device selector
            if audioEngine.blackHoleAvailable {
                HStack {
                    Text("Output:")
                    Picker("", selection: $audioEngine.selectedDeviceID) {
                        ForEach(audioEngine.availableDevices, id: \.id) { device in
                            Text(device.name).tag(device.id)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: audioEngine.selectedDeviceID) { _ in
                        // Restart engine if active to switch output device instantly
                        if audioEngine.isEnabled {
                            do {
                                try audioEngine.start()
                            } catch {
                                startErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                                showStartError = true
                            }
                        }
                    }
                }
            } else {
                // BlackHole not installed warning
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Audio driver not found")
                            .font(.callout)
                    }
                    
                    Button("Run Setup...") {
                        openWindow(id: "setup")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    .font(.caption)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }
            
            Divider()
            
            // Footer buttons
            HStack {
                Button("Preferences") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                
                Spacer()
                
                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
            .font(.caption)
        }
        .padding()
        .frame(width: 280)
        .task {
            // Auto-launch the setup wizard on first run (once per app session)
            guard !setupComplete, !audioEngine.hasAttemptedAutoSetup else { return }
            audioEngine.hasAttemptedAutoSetup = true
            
            // Short delay to ensure the menu bar icon is settled
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            openWindow(id: "setup")
            NSApp.activate(ignoringOtherApps: true)
        }
        .alert("Unable to Enable", isPresented: $showStartError) {
            Button("Run Setup…") {
                openWindow(id: "setup")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(startErrorMessage)
        }
    }
    
    private func toggleAudio() {
        if audioEngine.isEnabled {
            audioEngine.stop()
        } else {
            do {
                try audioEngine.start()
            } catch {
                startErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                showStartError = true
            }
        }
    }
}
