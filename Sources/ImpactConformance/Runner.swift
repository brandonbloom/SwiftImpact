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
    /// one before, as a parallel test runner would. Each unit's recording includes what the others
    /// ran while it did.
    case parallel
}

/// What a case did to each of its units in one mode.
public struct UnitResult: Codable, Sendable {
    public var unit: String
    /// Whether the unit returned something else after the edit.
    public var changed: Bool
    /// Whether the analysis said it needed to run, and why.
    public var selected: Bool
    public var reasons: [String]

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
        var files = [
            "Sources/ImpactCase/Unit.swift":
                try read(supportDirectory.appending(path: "ImpactCase/Unit.swift")),
            "Sources/ImpactCase/Shared.swift":
                try read(supportDirectory.appending(path: "ImpactCase/Shared.swift")),
            "Sources/Harness/main.swift":
                try read(supportDirectory.appending(path: "Harness/main.swift")),
        ]
        let probe = root.appending(path: "Sources/ImpactProbe")
        for file in try FileManager.default.contentsOfDirectory(
            at: probe, includingPropertiesForKeys: nil)
        where file.pathExtension == "swift" {
            files["Sources/ImpactProbe/\(file.lastPathComponent)"] = try read(file)
        }
        return files
    }

    /// Builds `testCase` before its edit and runs its units, recording what each returned and
    /// ran; then builds it after the edit, analyzes, and runs every unit again to check the
    /// analysis. Each unit is recorded as the test `<unit>@<mode>`.
    public func run(_ testCase: Case) throws -> CaseResult {
        let workspace = Workspace(
            directory: workDirectory.appending(path: testCase.name), support: try support())
        try? FileManager.default.removeItem(at: workspace.directory)

        // Runs every unit in `mode`, in the order the shared mode runs them, and returns what
        // each returned.
        var names: [String] = []
        func run(_ harness: URL, in mode: Mode) throws -> [String: String] {
            var outputs: [Workspace.Output] = []
            switch mode {
            case .shared:
                let pause = testCase.manifest.pauseBetweenUnits.map { ["\($0)"] } ?? []
                outputs = try workspace.run(harness, arguments: ["shared"] + pause)
                names = outputs.map(\.unit)
            case .isolated:
                outputs = try names.flatMap {
                    try workspace.run(harness, arguments: ["isolated", $0])
                }
            case .parallel:
                outputs = try workspace.run(harness, arguments: ["parallel"])
            }
            return Dictionary(uniqueKeysWithValues: outputs.map { ($0.unit, $0.output) })
        }

        try workspace.write(testCase, for: .before)
        var harness = try workspace.build()
        _ = try ImpactAnalysis.analyze(workspace.buildDirectory)
        var before: [Mode: [String: String]] = [:]
        for mode in Mode.allCases { before[mode] = try run(harness, in: mode) }
        // Every unit should now be recorded, and its result hold in the same build.
        let unchanged = try ImpactAnalysis.analyze(workspace.buildDirectory)
        for mode in Mode.allCases {
            for unit in names {
                let reasons = unchanged.reasonsToRun("\(unit)@\(mode.rawValue)")
                if !reasons.isEmpty {
                    throw CaseError(
                        name: testCase.name,
                        problem: "\(unit)@\(mode.rawValue) needs to run before the edit: "
                            + reasons.joined(separator: "; "))
                }
            }
        }

        try workspace.write(testCase, for: .after)
        harness = try workspace.build()
        let analysis = try ImpactAnalysis.analyze(workspace.buildDirectory)
        let incremental = try workspace.index()
        var after: [Mode: [String: String]] = [:]
        for mode in Mode.allCases { after[mode] = try run(harness, in: mode) }

        var result = CaseResult(units: [:], divergent: [])
        for mode in Mode.allCases {
            result.units[mode] = names.map { unit in
                let reasons = analysis.reasonsToRun("\(unit)@\(mode.rawValue)")
                return UnitResult(
                    unit: unit, changed: after[mode]![unit] != before[mode]![unit],
                    selected: !reasons.isEmpty, reasons: reasons)
            }
        }

        if checksCleanBuild {
            try workspace.clean()
            _ = try workspace.build()
            let clean = try workspace.index()
            let after = incremental
            let paths = Set(after.fingerprints.keys).union(clean.fingerprints.keys)
            result.divergent = paths.filter { after.fingerprints[$0] != clean.fingerprints[$0] }
                .sorted()
        }
        return result
    }
}
