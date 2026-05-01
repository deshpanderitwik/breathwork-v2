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
    dependencies: [
        .package(path: "../BreathRuntime"),
    ],
    targets: [
        .target(
            name: "BreathCore",
            dependencies: [
                .product(name: "BreathRuntime", package: "BreathRuntime"),
            ],
            path: "Sources/BreathCore"
        )
    ]
)
