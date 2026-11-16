import Foundation
import ImageIO
import Testing

/// HQ-463: Resonance ships its own icon. These read the repo's own files and unpack the .icns with `iconutil`
/// (no build, no window).
@Suite("App icon")
struct AppIconTests {
    static let root = InstallFootprintTests.root

    static func url(_ path: String) -> URL { root.appendingPathComponent(path) }

    static func pixelWidth(_ file: URL) -> Int? {
        guard let src = CGImageSourceCreateWithURL(file as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        else { return nil }
        return props[kCGImagePropertyPixelWidth] as? Int
    }

    @Test("Info.plist names the icon")
    func infoPlistNamesIcon() throws {
        let p = try InstallFootprintTests.plist()
        #expect(p["CFBundleIconFile"] as? String == "AppIcon")
    }

    @Test("AppIcon.icns holds every standard size from 16 to 1024 px")
    func icnsHasEveryStandardSize() throws {
        let icns = Self.url("Resources/AppIcon.icns")
        #expect(FileManager.default.fileExists(atPath: icns.path))

        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("resonance-icon-\(UUID().uuidString).iconset")
        defer { try? FileManager.default.removeItem(at: out) }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        proc.arguments = ["-c", "iconset", "-o", out.path, icns.path]
        try proc.run()
        proc.waitUntilExit()
        #expect(proc.terminationStatus == 0)

        let expected: [String: Int] = [
            "icon_16x16.png": 16, "icon_16x16@2x.png": 32,
            "icon_32x32.png": 32, "icon_32x32@2x.png": 64,
            "icon_128x128.png": 128, "icon_128x128@2x.png": 256,
            "icon_256x256.png": 256, "icon_256x256@2x.png": 512,
            "icon_512x512.png": 512, "icon_512x512@2x.png": 1024,
        ]
        for (name, px) in expected {
            #expect(Self.pixelWidth(out.appendingPathComponent(name)) == px, "\(name) should be \(px) px")
        }
    }

    @Test("The icon is rendered by a committed script")
    func renderScriptExists() {
        #expect(FileManager.default.fileExists(atPath: Self.url("scripts/render-icon.py").path))
    }

    @Test("build-app.sh copies the icon into the bundle; the DMG volume uses it too")
    func buildScriptsShipIcon() throws {
        #expect(try InstallFootprintTests.text("scripts/build-app.sh").contains("Resources/AppIcon.icns"))
        #expect(try InstallFootprintTests.text("build-dmg.sh").contains(".VolumeIcon.icns"))
    }

    @Test("Previews at 16, 32, 128 and 512 px are saved for review")
    func previewsExist() {
        for px in [16, 32, 128, 512] {
            let f = Self.url("docs/icon/preview-\(px).png")
            #expect(Self.pixelWidth(f) == px, "docs/icon/preview-\(px).png")
        }
    }
}
