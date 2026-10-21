// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SwiftImpact",
    platforms: [.macOS("15.0"), .iOS("18.0"), .tvOS("18.0")],
    products: [
        // Linked into the process under test: records which functions a unit of work runs.
        .library(name: "ImpactProbe", targets: ["ImpactProbe"]),
        // Used by the harness: maps footprints to source files and finds what changed.
        .library(name: "SwiftImpact", targets: ["SwiftImpact"]),
        .executable(name: "swift-impact", targets: ["swift-impact"]),
    ],
    targets: [
        .target(name: "ImpactProbe"),
        .target(name: "SwiftImpact"),
        .executableTarget(name: "swift-impact", dependencies: ["SwiftImpact"]),
        .testTarget(name: "SwiftImpactTests", dependencies: ["SwiftImpact"]),
    ]
)
