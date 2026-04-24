// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Breathe",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../swift/BreathCore"),
    ],
    targets: [
        .executableTarget(
            name: "Breathe",
            dependencies: [
                .product(name: "BreathCore", package: "BreathCore"),
            ],
            path: "Sources/Breathe"
        )
    ]
)
