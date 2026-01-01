import SwiftUI
import AVFoundation

struct SetupView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("setupComplete") private var setupComplete = false
    @State private var currentStep = 0
    @State private var blackHoleInstalled = false
    @State private var isChecking = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            // Content
            Group {
                switch currentStep {
                case 0:
                    welcomeStep
                case 1:
                    driverStep
                case 2:
                    configureStep
                case 3:
                    completeStep
                default:
                    completeStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Navigation
            navigationButtons
        }
        .frame(width: 500, height: 400)
        .onAppear {
            checkBlackHoleInstalled()
        }
    }
    
    // MARK: - Header
    
    var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            
            Text("Resonance Setup")
                .font(.title)
                .fontWeight(.semibold)
            
            // Progress dots
            HStack(spacing: 8) {
                ForEach(0..<4) { index in
                    Circle()
                        .fill(index <= currentStep ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 8)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Steps
    
    var welcomeStep: some View {
        VStack(spacing: 16) {
            Text("Welcome to Resonance")
                .font(.headline)
            
            Text("Resonance converts all your Mac audio to 432Hz tuning in real-time, creating a more harmonious listening experience.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 32)
            
            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "music.note", text: "Works with any audio source")
                featureRow(icon: "hare", text: "Real-time processing, no delay")
                featureRow(icon: "menubar.rectangle", text: "Lives in your menu bar")
            }
            .padding(.top, 16)
        }
        .padding()
    }
    
    var driverStep: some View {
        VStack(spacing: 16) {
            Text("Audio Driver Required")
                .font(.headline)
            
            if isChecking {
                ProgressView()
                    .padding()
                Text("Checking for BlackHole driver...")
                    .foregroundColor(.secondary)
            } else if blackHoleInstalled {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
                Text("BlackHole driver is installed!")
                    .foregroundColor(.green)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)
                
                Text("BlackHole audio driver is required")
                    .foregroundColor(.secondary)
                
                Text("Please install it from the DMG, then click 'Check Again'")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                HStack(spacing: 16) {
                    Button("Open DMG Location") {
                        // If running from a mounted DMG, this opens the mounted folder.
                        // If already installed in /Applications, this opens /Applications.
                        let containerURL = Bundle.main.bundleURL.deletingLastPathComponent()
                        NSWorkspace.shared.open(containerURL)
                    }
                    
                    Button("Check Again") {
                        checkBlackHoleInstalled()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 8)
            }
        }
        .padding()
    }
    
    var configureStep: some View {
        VStack(spacing: 16) {
            Text("Configure Audio Output")
                .font(.headline)
            
            Text("For best results, create a Multi-Output Device:")
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
                instructionRow(number: 1, text: "Open Audio MIDI Setup (Spotlight → 'Audio MIDI')")
                instructionRow(number: 2, text: "Click '+' → 'Create Multi-Output Device'")
                instructionRow(number: 3, text: "Check BlackHole 2ch AND your speakers")
                instructionRow(number: 4, text: "In System Settings → Sound → Output, select your Multi-Output Device")
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            HStack(spacing: 12) {
                Button("Open Audio MIDI Setup") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app"))
                }
                
                Button("Open Sound Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.sound") {
                        NSWorkspace.shared.open(url)
                    }
                }
                
                Button("I've done this") {
                    withAnimation {
                        currentStep = 3
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
    
    var completeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)
            
            Text("You're All Set!")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Click the waveform icon in your menu bar to enable 432Hz audio conversion.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 32)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick Start:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Image(systemName: "1.circle.fill")
                    Text("Select 'BlackHole 2ch' as input")
                }
                .font(.caption)
                
                HStack {
                    Image(systemName: "2.circle.fill")
                    Text("Click 'Enable'")
                }
                .font(.caption)
                
                HStack {
                    Image(systemName: "3.circle.fill")
                    Text("Play any audio and enjoy 432Hz!")
                }
                .font(.caption)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .padding()
    }
    
    // MARK: - Navigation
    
    var navigationButtons: some View {
        HStack {
            if currentStep > 0 {
                Button("Back") {
                    withAnimation {
                        currentStep -= 1
                    }
                }
            }
            
            Spacer()
            
            if currentStep < 3 {
                Button(currentStep == 0 ? "Get Started" : "Next") {
                    withAnimation {
                        currentStep += 1
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(currentStep == 1 && !blackHoleInstalled)
            } else {
                Button("Finish") {
                    setupComplete = true
                    // Specifically target the setup window to close it
                    if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "setup" }) {
                        window.close()
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Helpers
    
    func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(.accentColor)
            Text(text)
        }
    }
    
    func instructionRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number).")
                .fontWeight(.bold)
                .frame(width: 20)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }
    
    func checkBlackHoleInstalled() {
        isChecking = true
        
        Task { @MainActor in
            // Check if BlackHole device exists on the MainActor
            let devices = AudioDeviceManager.shared.getAvailableDevices()
            let deviceExists = devices.contains { $0.name.lowercased().contains("blackhole") }
            
            self.blackHoleInstalled = deviceExists
            self.isChecking = false
            
            // Auto-advance if installed
            if deviceExists && currentStep == 1 {
                withAnimation {
                    currentStep = 2
                }
            }
        }
    }
}
