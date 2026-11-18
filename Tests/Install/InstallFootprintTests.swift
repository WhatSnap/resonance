import Foundation
import Testing

/// HQ-435: the 2.0 app installs in one step. These read the repo's own files (no build, no device, no window).
@Suite("Install footprint")
struct InstallFootprintTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func text(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)
    }

    static func plist() throws -> [String: Any] {
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test("Info.plist asks for audio capture, not the microphone, on macOS 14.4+")
    func infoPlistIsTheTwoPointOhApp() throws {
        let p = try Self.plist()
        #expect((p["NSAudioCaptureUsageDescription"] as? String)?.isEmpty == false)
        #expect(p["NSMicrophoneUsageDescription"] == nil)
        #expect(p["LSMinimumSystemVersion"] as? String == "14.4")
        #expect(p["CFBundleIdentifier"] as? String == "com.resonance.app")
        #expect(p["CFBundleShortVersionString"] as? String == "2.0")
        #expect(p["CFBundleExecutable"] as? String == "Resonance")
        #expect(p["LSUIElement"] as? Bool == true)
    }

    @Test("No microphone entitlement ships")
    func noMicrophoneEntitlement() throws {
        if Self.exists("Resources/Resonance.entitlements") {
            #expect(!(try Self.text("Resources/Resonance.entitlements")).contains("audio-input"))
        }
    }

    @Test("One build path: build-app.sh copies Resources/Info.plist and build-dmg.sh calls build-app.sh")
    func oneBuildPath() throws {
        let app = try Self.text("scripts/build-app.sh")
        #expect(app.contains("Resources/Info.plist"))
        #expect(!app.contains("<plist"), "build-app.sh must not carry its own copy of the plist")
        let dmg = try Self.text("build-dmg.sh")
        #expect(dmg.contains("scripts/build-app.sh"))
        #expect(!dmg.contains("<plist") && !dmg.contains("swift build"))
    }

    @Test("No BlackHole or Multi-Output in the app, the DMG script or the README")
    func noBlackHole() throws {
        let sources = Self.root.appendingPathComponent("Sources")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        for case let url as URL in files where url.pathExtension == "swift" {
            let body = try String(contentsOf: url, encoding: .utf8).lowercased()
            #expect(!body.contains("blackhole"), "\(url.lastPathComponent) mentions BlackHole")
        }
        for path in ["build-dmg.sh", "README.md"] {
            let body = try Self.text(path).lowercased()
            #expect(!body.contains("blackhole"), "\(path) mentions BlackHole")
            #expect(!body.contains("multi-output"), "\(path) mentions Multi-Output")
        }
    }

    @Test("README and the DMG's README point a first-time user through Gatekeeper and the audio prompt")
    func firstOpenSteps() throws {
        let readme = try Self.text("README.md")
        #expect(readme.contains("https://github.com/WhatSnap/resonance/releases/latest"))
        for body in [readme, try Self.text("build-dmg.sh")] {
            #expect(body.contains("Privacy & Security"))
            #expect(body.contains("Open Anyway"))
            #expect(body.contains("audio recording"))
            #expect(!body.contains("right-click"), "right-click > Open no longer bypasses Gatekeeper on macOS 15")
        }
    }

    @Test("Dead DSP code and the 1.0 constants are gone")
    func deadCodeIsGone() {
        for path in ["Core", "Sources/Audio/FFTProcessor.swift", "Sources/Audio/PitchShifter.swift",
                     "Sources/UI/SetupView.swift", "Sources/Utils/Constants.swift"] {
            #expect(!Self.exists(path), "\(path) still exists")
        }
    }

    @Test("Package.swift targets macOS 14.4")
    func packageMinimum() throws {
        #expect(try Self.text("Package.swift").contains(#".macOS("14.4")"#))
    }
}
