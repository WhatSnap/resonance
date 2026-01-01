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
        .executableTarget(
            name: "Resonance",
            path: "Sources"),
    ]
)
