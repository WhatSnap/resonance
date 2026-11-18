// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Resonance",
    platforms: [
        .macOS("14.4")
    ],
    products: [
        .executable(name: "Resonance", targets: ["Resonance"])
    ],
    dependencies: [
        // Lock-free atomics for the real-time ring buffer (HQ-432). `Synchronization.Atomic` needs macOS 15.
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0"),
    ],
    targets: [
        .target(name: "ResonanceCore", dependencies: [.product(name: "Atomics", package: "swift-atomics")], path: "Library"),
        .executableTarget(name: "Resonance", dependencies: ["ResonanceCore"], path: "Sources"),
        .testTarget(name: "ResonanceCoreTests", dependencies: ["ResonanceCore"], path: "Tests"),
    ]
)
