// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Breathe",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Breathe",
            path: "Sources/Breathe"
        )
    ]
)
