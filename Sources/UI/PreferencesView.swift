import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var audioEngine: AudioEngine
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Resonance Preferences")
                .font(.title)
            
            Text("Version 1.0.0 (MVP)")
                .foregroundColor(.secondary)
            
            Form {
                Section(header: Text("Audio Engine")) {
                    HStack {
                        Text("Status:")
                        Text(audioEngine.isEnabled ? "Active" : "Inactive")
                            .foregroundColor(audioEngine.isEnabled ? .green : .gray)
                    }
                    
                    Toggle("Enable 432Hz Pitch Shift", isOn: Binding(
                        get: { audioEngine.isEnabled },
                        set: {
                            if $0 {
                                do { try audioEngine.start() }
                                catch { /* Menu bar UI shows errors; keep prefs toggle simple. */ }
                            } else {
                                audioEngine.stop()
                            }
                        }
                    ))
                }
                
                Section(header: Text("General")) {
                    Button("Reset Setup Wizard") {
                        UserDefaults.standard.set(false, forKey: "setupComplete")
                    }
                }
            }
            .formStyle(.grouped)
            
            Button("Close") {
                NSApp.keyWindow?.close()
            }
            .padding(.bottom)
        }
        .padding()
        .frame(width: 400, height: 400)
    }
}
