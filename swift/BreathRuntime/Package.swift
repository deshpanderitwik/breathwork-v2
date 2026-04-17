// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BreathRuntime",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "BreathRuntime", targets: ["BreathRuntime"])
    ],
    targets: [
        .target(
            name: "BreathRuntime",
            resources: [
                // The TS core bundled as an IIFE. Built by `pnpm --filter
                // @breathe/core build` from packages/core/dist/core.iife.js
                // and copied here. See scripts/sync-core.sh (Phase 1).
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "BreathRuntimeTests",
            dependencies: ["BreathRuntime"]
        ),
    ]
)
