// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SwiftImpact",
    platforms: [.macOS("15.0"), .iOS("18.0"), .tvOS("18.0")],
    products: [
        // Linked into the process that runs the tests: records what each test runs.
        .library(name: "ImpactProbe", targets: ["ImpactProbe"]),
        // Used by the harness: which tests' last results still hold for the current build.
        .library(name: "ImpactAnalysis", targets: ["ImpactAnalysis"]),
    ],
    targets: [
        .target(name: "ImpactProbe"),
        .target(name: "ImpactAnalysis"),
        // Runs the conformance cases in Conformance/Cases.
        .target(name: "ImpactConformance", dependencies: ["ImpactAnalysis"]),
        .executableTarget(
            name: "swift-impact-conformance", dependencies: ["ImpactConformance"]),
        .testTarget(name: "ImpactProbeTests", dependencies: ["ImpactProbe"]),
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
