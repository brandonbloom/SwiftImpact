import Foundation
import ImpactAnalysis

/// How units share processes when they run.
public enum Mode: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable {
    /// All units in one process, in order, as a test runner would. State a unit initializes, such
    /// as a global, is already there for the units after it.
    case shared
    /// Each unit in a process of its own.
    case isolated
    /// All units in one process at once, each on a thread of its own and starting 20 ms after the
    /// one before, as a parallel test runner would. Each unit's footprint includes what the others
    /// ran while it did.
    case parallel
}

/// What a case did to each of its units in one mode.
public struct UnitResult: Codable, Sendable {
    public var unit: String
    /// Whether the unit returned something else after the edit.
    public var changed: Bool
    /// Whether selection chose it, and why.
    public var selected: Bool
    public var reasons: [String]
    /// The number of objects in its footprint.
    public var footprint: Int

    public var escaped: Bool { changed && !selected }
}

/// A case's result in one environment.
public struct CaseResult: Codable, Sendable {
    public var units: [Mode: [UnitResult]]
    /// Objects whose fingerprints differ between the incremental build after the edit and a clean
    /// one. Selection trusts incremental builds, so any is a problem.
    public var divergent: [String]
}

/// Runs cases, each in its own package under a working directory.
public struct Runner: Sendable {
    /// The repository's root, holding the probe's source and the support files.
    public let root: URL
    public let workDirectory: URL
    /// Whether to rebuild after the edit from clean, to check the incremental build.
    public var checksCleanBuild = true

    public init(root: URL, workDirectory: URL) {
        self.root = root
        self.workDirectory = workDirectory
    }

    /// The files every case's package shares.
    func support() throws -> [String: String] {
        let supportDirectory = root.appending(path: "Conformance/Support")
        func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }
        return [
            "Sources/ImpactProbe/ImpactProbe.swift":
                try read(root.appending(path: "Sources/ImpactProbe/ImpactProbe.swift")),
            "Sources/ImpactCase/Unit.swift":
                try read(supportDirectory.appending(path: "ImpactCase/Unit.swift")),
            "Sources/Harness/main.swift":
                try read(supportDirectory.appending(path: "Harness/main.swift")),
        ]
    }

    /// Builds `testCase` before its edit and runs its units, recording what each returned and
    /// ran; then builds it after the edit, selects, and runs every unit again to check selection.
    public func run(_ testCase: Case) throws -> CaseResult {
        let workspace = Workspace(
            directory: workDirectory.appending(path: testCase.name), support: try support())
        try? FileManager.default.removeItem(at: workspace.directory)

        // Runs every unit in `mode`, in the order the shared mode runs them.
        var names: [String] = []
        func run(_ harness: URL, in mode: Mode) throws -> [Workspace.Record] {
            switch mode {
            case .shared:
                let pause = testCase.manifest.pauseBetweenUnits.map { ["--pause", "\($0)"] }
                let records = try workspace.run(harness, arguments: pause ?? [])
                names = records.map(\.unit)
                return records
            case .isolated:
                return try names.flatMap { try workspace.run(harness, arguments: [$0]) }
            case .parallel:
                let records = try workspace.run(harness, arguments: ["--parallel"])
                return records.sorted {
                    names.firstIndex(of: $0.unit)! < names.firstIndex(of: $1.unit)!
                }
            }
        }

        try workspace.write(testCase, for: .before)
        var harness = try workspace.build()
        let before = try workspace.index()
        var recorded: [Mode: [Workspace.Record]] = [:]
        for mode in Mode.allCases { recorded[mode] = try run(harness, in: mode) }

        try workspace.write(testCase, for: .after)
        harness = try workspace.build()
        let after = try workspace.index()
        var outputs: [Mode: [String: String]] = [:]
        for mode in Mode.allCases {
            outputs[mode] = Dictionary(
                uniqueKeysWithValues: try run(harness, in: mode).map { ($0.unit, $0.output) })
        }

        var result = CaseResult(units: [:], divergent: [])
        for mode in Mode.allCases {
            let records = recorded[mode]!
            let footprints = Dictionary(
                uniqueKeysWithValues: records.map {
                    ($0.unit, before.footprint(of: $0.functions, sources: $0.sources))
                })
            let affected = ImpactGraph(index: before, footprints: footprints).affected(in: after)
            result.units[mode] = records.map {
                UnitResult(
                    unit: $0.unit, changed: outputs[mode]![$0.unit] != $0.output,
                    selected: affected[$0.unit] != nil,
                    reasons: (affected[$0.unit] ?? []).map { ($0 as NSString).lastPathComponent },
                    footprint: footprints[$0.unit]!.objects.count)
            }
        }

        if checksCleanBuild {
            try workspace.clean()
            _ = try workspace.build()
            let clean = try workspace.index()
            let paths = Set(after.fingerprints.keys).union(clean.fingerprints.keys)
            result.divergent = paths.filter { after.fingerprints[$0] != clean.fingerprints[$0] }
                .sorted()
        }
        return result
    }
}
