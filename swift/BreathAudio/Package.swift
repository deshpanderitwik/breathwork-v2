// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BreathAudio",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "BreathAudio", targets: ["BreathAudio"])
    ],
    targets: [
        .target(name: "BreathAudio"),
        .testTarget(name: "BreathAudioTests", dependencies: ["BreathAudio"]),
    ]
)
