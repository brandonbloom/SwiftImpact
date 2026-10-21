// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "TestImpact",
  platforms: [.macOS("15.0"), .iOS("18.0"), .tvOS("18.0")],
  products: [
    // Linked into the process under test: records which functions a unit of work runs.
    .library(name: "ImpactProbe", targets: ["ImpactProbe"]),
    // Used by the harness: maps footprints to source files and finds what changed.
    .library(name: "TestImpact", targets: ["TestImpact"]),
    .executable(name: "test-impact", targets: ["test-impact"]),
  ],
  targets: [
    .target(name: "ImpactProbe"),
    .target(name: "TestImpact"),
    .executableTarget(name: "test-impact", dependencies: ["TestImpact"]),
    .testTarget(name: "TestImpactTests", dependencies: ["TestImpact"]),
  ]
)
