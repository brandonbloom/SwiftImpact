import Foundation

/// Which tests' last results still hold for the code as it's built now.
///
/// ```swift
/// let analysis = try ImpactAnalysis.analyze(URL(filePath: ".build"))
/// if analysis.isImpacted("MyModule/ParserTests/parsesNumbers") {
///     // Run it.
/// }
/// ```
///
/// Tests are recorded by `ImpactProbe` in a process launched with ``environment(for:)``, which
/// saves the recordings in the build directory. Analyze before each run: an analysis takes stock
/// of the build its run is about to use, which the next analysis needs to make sense of that
/// run's recordings.
public struct ImpactAnalysis: Sendable {
    /// Arguments to add to `swift build` or `swift test` for the code under test.
    public static let buildArguments = ["-Xswiftc", "-profile-generate"]

    /// Environment variables to launch the process under test with, so it records into the
    /// build in `buildDirectory`.
    public static func environment(for buildDirectory: URL) -> [String: String] {
        [
            // `ImpactProbe` saves recordings in the directory this names.
            "SWIFTIMPACT_RECORDINGS": Store(buildDirectory: buildDirectory).recordings.path,
            // The instrumentation would otherwise write a profile that nothing reads.
            "LLVM_PROFILE_FILE": "/dev/null",
        ]
    }

    /// Each recorded test's reasons to run, empty if its last result holds.
    let reasons: [String: [String]]

    /// The number of tests whose latest recording this analysis could use. Zero means it knows
    /// nothing: no run has been recorded in this build directory, or the process running the
    /// tests isn't recording. For debugging selection.
    package let recordedTestCount: Int

    /// Takes stock of the build in `buildDirectory` as it is now, and of the recordings made in
    /// it. Throws if the build can't be read; then run every test.
    public static func analyze(_ buildDirectory: URL) throws -> ImpactAnalysis {
        let store = Store(buildDirectory: buildDirectory)
        let current = try Snapshot.all(in: buildDirectory)
        guard !current.isEmpty else {
            throw AnalysisError(
                description: "\(buildDirectory.path) has no build made with "
                    + "ImpactAnalysis.buildArguments")
        }
        try store.save(current)
        let snapshots = store.snapshots()
        var reasons: [String: [String]] = [:]
        var recordedTestCount = 0
        var needed = Set(current.map(\.key))
        let recordings = store.latestRecordings()
        for (test, recording) in recordings {
            let recorded = snapshots.first { Set($0.images).isSuperset(of: recording.images) }
            if let recorded { needed.insert(recorded.key) }
            let assessment = assess(recording, recordedIn: recorded, current: current)
            reasons[test] = assessment.reasons
            if assessment.usable { recordedTestCount += 1 }
        }
        store.removeSnapshots(except: needed)
        var withDependencies = reasons
        for test in reasons.keys {
            withDependencies[test]! += dependencyReasons(
                of: test, dependencies: { recordings[$0]?.dependsOn ?? [] }, reasons: reasons)
        }
        return ImpactAnalysis(reasons: withDependencies, recordedTestCount: recordedTestCount)
    }

    /// Whether a change may have impacted `test`, so it needs to run: `true` unless its last
    /// result still holds, including for a test the analysis knows nothing about.
    public func isImpacted(_ test: String) -> Bool {
        !reasonsToRun(test).isEmpty
    }

    /// Why `test` is impacted or not, for a person to read, such as
    /// `"MyModule/Parser.swift changed"` or `"its last result still holds"`.
    ///
    /// For display only: the wording may change between versions, so don't parse it.
    public func explain(_ test: String) -> String {
        let reasons = reasonsToRun(test)
        return reasons.isEmpty ? "its last result still holds" : reasons.joined(separator: "; ")
    }

    /// Why `test` needs to run, one reason per cause; empty if its last result still holds.
    package func reasonsToRun(_ test: String) -> [String] {
        reasons[test] ?? ["it has no recording"]
    }

    /// Why `test` needs to run because of the recordings it depends on, transitively: each one
    /// that's impacted or has no recording. `reasons` holds each recorded test's own reasons.
    static func dependencyReasons(
        of test: String, dependencies: (String) -> [String], reasons: [String: [String]]
    ) -> [String] {
        var result: [String] = []
        var seen: Set = [test]
        var pending = dependencies(test)
        while let dependency = pending.popLast() {
            guard seen.insert(dependency).inserted else { continue }
            guard let own = reasons[dependency] else {
                result.append("it depends on \(dependency), which has no recording")
                continue
            }
            if !own.isEmpty { result.append("it depends on \(dependency), which is impacted") }
            pending += dependencies(dependency)
        }
        return result.sorted()
    }

    /// Whether the analysis could use `recording`, and why its test needs to run, given the
    /// snapshot of the build it was recorded in and of the builds there are now.
    static func assess(
        _ recording: Recording, recordedIn recorded: Snapshot?, current: [Snapshot]
    ) -> (usable: Bool, reasons: [String]) {
        guard let recorded else {
            return (false, ["it was recorded in a build that wasn't analyzed"])
        }
        guard let now = current.first(where: { $0.configuration == recorded.configuration }) else {
            return (false, ["its build configuration, \(recorded.configuration), is gone"])
        }
        let footprint = recorded.index.footprint(
            of: recording.functions, sources: recording.declaredIn.map { [$0] } ?? [])
        if footprint.unattributed > 0 {
            return (false, ["it ran code its build couldn't attribute to a file"])
        }
        let changedFiles = footprint.changes(in: now.index).map(recorded.index.fileID(ofObject:))
        let changedConformances = footprint.uses(
            recorded.index.allConformances.symmetricDifference(now.index.allConformances))
        return (
            true,
            changedFiles.sorted().map { "\($0) changed" }
                + changedConformances.map { "\(describe(conformance: $0)) came or went" }
        )
    }
}

/// Why a build can't be analyzed.
struct AnalysisError: Error, CustomStringConvertible {
    let description: String
}
