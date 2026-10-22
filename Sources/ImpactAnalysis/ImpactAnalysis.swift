import Foundation

/// Which tests' last results still hold for the code as it's built now.
///
/// ```swift
/// let analysis = try ImpactAnalysis.analyze(URL(filePath: ".build"))
/// if let reason = analysis.reasonToRun("MyModule/ParserTests/parsesNumbers") {
///     print(reason)  // For example: "MyModule/Parser.swift changed".
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

    /// Each recorded test's reason to run, or `nil` if its last result holds.
    let reasons: [String: String?]

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
        var reasons: [String: String?] = [:]
        var needed = Set(current.map(\.key))
        for (test, recording) in store.latestRecordings() {
            let recorded = snapshots.first { Set($0.images).isSuperset(of: recording.images) }
            if let recorded { needed.insert(recorded.key) }
            reasons[test] = reason(for: recording, recordedIn: recorded, current: current)
        }
        store.removeSnapshots(except: needed)
        return ImpactAnalysis(reasons: reasons)
    }

    /// Why `test` needs to run, for a person to read; `nil` if its last result still holds.
    public func reasonToRun(_ test: String) -> String? {
        guard let reason = reasons[test] else { return "it has no recording" }
        return reason
    }

    /// Why the test `recording` describes needs to run, given the snapshot of the build it was
    /// recorded in and of the builds there are now.
    static func reason(
        for recording: Recording, recordedIn recorded: Snapshot?, current: [Snapshot]
    ) -> String? {
        guard let recorded else { return "it was recorded in a build that wasn't analyzed" }
        guard let now = current.first(where: { $0.configuration == recorded.configuration }) else {
            return "its build configuration, \(recorded.configuration), is gone"
        }
        let footprint = recorded.index.footprint(
            of: recording.functions, sources: [recording.declaredIn])
        if footprint.unattributed > 0 {
            return "it ran code its build couldn't attribute to a file"
        }
        let changedFiles = footprint.changes(in: now.index).map(recorded.index.fileID(ofObject:))
        let changedConformances = footprint.uses(
            recorded.index.allConformances.symmetricDifference(now.index.allConformances))
        var reasons: [String] = []
        if !changedFiles.isEmpty {
            reasons.append("\(list(changedFiles)) changed")
        }
        if !changedConformances.isEmpty {
            reasons.append("\(list(changedConformances.map(describe(conformance:)))) came or went")
        }
        return reasons.isEmpty ? nil : reasons.joined(separator: "; ")
    }
}

/// Why a build can't be analyzed.
struct AnalysisError: Error, CustomStringConvertible {
    let description: String
}

/// `items` in a sentence, naming at most three.
func list(_ items: [String]) -> String {
    let sorted = items.sorted()
    switch sorted.count {
    case 1: return sorted[0]
    case 2: return "\(sorted[0]) and \(sorted[1])"
    case 3: return "\(sorted[0]), \(sorted[1]), and \(sorted[2])"
    default: return "\(sorted[0]), \(sorted[1]), and \(sorted.count - 2) more"
    }
}
