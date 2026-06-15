// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CodexUsageMonitor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CodexUsageCore", targets: ["CodexUsageCore"]),
        .executable(name: "CodexUsageCLI", targets: ["CodexUsageCLI"]),
        .executable(name: "CodexUsageMenuBar", targets: ["CodexUsageMenuBar"]),
        .executable(name: "CodexUsageWidgets", targets: ["CodexUsageWidgets"])
    ],
    targets: [
        .target(name: "CodexUsageCore"),
        .executableTarget(
            name: "CodexUsageCLI",
            dependencies: ["CodexUsageCore"]
        ),
        .executableTarget(
            name: "CodexUsageMenuBar",
            dependencies: ["CodexUsageCore"]
        ),
        .executableTarget(
            name: "CodexUsageWidgets",
            dependencies: ["CodexUsageCore"],
            swiftSettings: [
                .unsafeFlags(["-application-extension"])
            ]
        )
    ]
)
