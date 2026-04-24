// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BreathCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "BreathCore", targets: ["BreathCore"])
    ],
    targets: [
        .target(name: "BreathCore", path: "Sources/BreathCore")
    ]
)
