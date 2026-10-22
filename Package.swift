// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SwiftImpact",
    platforms: [.macOS("15.0"), .iOS("18.0"), .tvOS("18.0")],
    products: [
        // Linked into the process under test: records which functions a unit of work runs.
        .library(name: "ImpactProbe", targets: ["ImpactProbe"]),
        // Used by the harness: maps footprints to source files and finds what changed.
        .library(name: "ImpactAnalysis", targets: ["ImpactAnalysis"]),
        .executable(name: "swift-impact", targets: ["swift-impact"]),
    ],
    targets: [
        .target(name: "ImpactProbe"),
        .target(name: "ImpactAnalysis"),
        .executableTarget(name: "swift-impact", dependencies: ["ImpactAnalysis"]),
        // Runs the conformance cases in Conformance/Cases.
        .target(name: "ImpactConformance", dependencies: ["ImpactAnalysis"]),
        .executableTarget(
            name: "swift-impact-conformance", dependencies: ["ImpactConformance"]),
        .testTarget(name: "ImpactAnalysisTests", dependencies: ["ImpactAnalysis"]),
        .testTarget(name: "ImpactConformanceTests", dependencies: ["ImpactConformance"]),
        // `swift package docs` builds the libraries' documentation into one archive.
        .plugin(
            name: "Docs",
            capability: .command(
                intent: .custom(
                    verb: "docs", description: "Build the documentation into one archive."))),
    ]
)
