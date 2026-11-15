// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Resonance",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Resonance", targets: ["Resonance"])
    ],
    targets: [
        .target(name: "ResonanceCore", path: "Library"),
        .executableTarget(name: "Resonance", dependencies: ["ResonanceCore"], path: "Sources"),
        .testTarget(name: "ResonanceCoreTests", dependencies: ["ResonanceCore"], path: "Tests"),
    ]
)
