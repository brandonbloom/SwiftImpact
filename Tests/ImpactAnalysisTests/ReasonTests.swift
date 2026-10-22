import Testing

@testable import ImpactAnalysis

/// A snapshot of a build of `Units/A.swift` and `Units/B.swift`, whose functions 1 and 2 they
/// define, with `fingerprints`, `conformances`, and the types `A.swift` uses and `definedTypes`
/// defines.
func snapshot(
    images: [String], fingerprints: [String: String], conformances: [String] = [],
    types: [String] = ["_$s5Units3TagV"], definedTypes: [String] = ["_$s5Units3TagV"]
) -> Snapshot {
    Snapshot(
        configuration: "Debug", images: images,
        index: BuildIndex(
            fingerprints: fingerprints, owners: [1: ["A.o"], 2: ["B.o"]],
            sources: ["Units/A.swift": "A.o", "Units/B.swift": "B.o"],
            conformances: ["B.o": conformances], types: ["A.o": types],
            definedTypes: ["A.o": definedTypes]))
}

func recording(
    images: [String] = ["U1"], functions: [UInt64] = [1], declaredIn: String? = "Units/A.swift"
) -> Recording {
    Recording(
        version: 1, test: "t", declaredIn: declaredIn, dependsOn: [], time: 0, images: images,
        functions: functions)
}

/// Each reason `recording` gives to run, comparing `before` with `after`.
func reasons(
    _ recording: Recording = recording(), from before: Snapshot, to after: Snapshot
) -> [String] {
    ImpactAnalysis.assess(recording, recordedIn: before, current: [after]).reasons.all
}

let unchanged = ["A.o": "1", "B.o": "1"]
let description = "_$s5Units3TagVs23CustomStringConvertiblesMc"

@Test func testsWithoutRecordingsAreImpacted() {
    let analysis = ImpactAnalysis(
        reasons: ["recorded": Reasons(), "changed": Reasons(changedFiles: ["Units/A.swift"])],
        recordedTestCount: 2)
    #expect(!analysis.isImpacted("recorded"))
    #expect(analysis.isImpacted("changed"))
    #expect(analysis.isImpacted("unknown"))
    #expect(analysis.explain("recorded") == "its last result still holds")
    #expect(analysis.explain("changed") == "Units/A.swift changed")
    #expect(analysis.explain("unknown") == "it has no recording")
}

@Test func resultHoldsWhenNothingItUsedChanged() {
    let before = snapshot(images: ["U1"], fingerprints: unchanged)
    let after = snapshot(images: ["U2"], fingerprints: ["A.o": "1", "B.o": "2"])
    #expect(reasons(from: before, to: after).isEmpty)
}

@Test func changedFilesAreNamed() {
    let before = snapshot(images: ["U1"], fingerprints: unchanged)
    let after = snapshot(images: ["U2"], fingerprints: ["A.o": "2", "B.o": "1"])
    #expect(reasons(from: before, to: after) == ["Units/A.swift changed"])
}

@Test func conformancesOfUsedTypesAreNamed() {
    let before = snapshot(images: ["U1"], fingerprints: unchanged)
    let after = snapshot(images: ["U2"], fingerprints: unchanged, conformances: [description])
    #expect(
        reasons(from: before, to: after)
            == ["the conformance Units.Tag : Swift.CustomStringConvertible came or went"])
}

@Test func conformancesOfNewOrGoneTypesDontCount() {
    let before = snapshot(images: ["U1"], fingerprints: unchanged, definedTypes: [])
    let after = snapshot(images: ["U2"], fingerprints: unchanged, conformances: [description])
    #expect(reasons(from: before, to: after).isEmpty)
    #expect(reasons(from: after, to: before).isEmpty)
}

@Test func conformancesOfExternalTypesCount() {
    let before = snapshot(images: ["U1"], fingerprints: unchanged, definedTypes: [])
    let after = snapshot(
        images: ["U2"], fingerprints: unchanged, conformances: [description], definedTypes: [])
    #expect(reasons(from: before, to: after).count == 1)
}

@Test func nestedTypesDontMatchTheirParents() {
    let types = ["_$s5Units3TagV", "_$s5Units3TagV6StatusO"]
    let nested = "_$s5Units3TagV6StatusOSQAAMc"
    let before = snapshot(
        images: ["U1"], fingerprints: unchanged, types: ["_$s5Units3TagV"], definedTypes: types)
    let after = snapshot(
        images: ["U2"], fingerprints: unchanged, conformances: [nested],
        types: ["_$s5Units3TagV"], definedTypes: types)
    #expect(reasons(from: before, to: after).isEmpty)
}

@Test func unknownBuildsAndCodeMeanRunning() {
    let current = snapshot(images: ["U2"], fingerprints: unchanged)
    let unanalyzed = ImpactAnalysis.assess(recording(), recordedIn: nil, current: [current])
    #expect(!unanalyzed.usable)
    #expect(unanalyzed.reasons.all == ["it was recorded in a build that wasn't analyzed"])
    let unattributed = ImpactAnalysis.assess(
        recording(functions: [9]), recordedIn: current, current: [current])
    #expect(!unattributed.usable)
    #expect(unattributed.reasons.all == ["it ran code its build couldn't attribute to a file"])
    #expect(ImpactAnalysis.assess(recording(), recordedIn: current, current: [current]).usable)
}

@Test func theDeclaringFileCountsOnlyWhenKnown() {
    let before = snapshot(images: ["U1"], fingerprints: unchanged)
    let after = snapshot(images: ["U2"], fingerprints: ["A.o": "2", "B.o": "1"])
    #expect(
        reasons(recording(functions: [2]), from: before, to: after) == ["Units/A.swift changed"])
    #expect(
        reasons(recording(functions: [2], declaredIn: nil), from: before, to: after).isEmpty)
}

@Test func eachChangedFileIsAReasonOfItsOwn() {
    let before = snapshot(images: ["U1"], fingerprints: unchanged)
    let after = snapshot(images: ["U2"], fingerprints: ["A.o": "2", "B.o": "2"])
    #expect(
        reasons(recording(functions: [1, 2]), from: before, to: after)
            == ["Units/A.swift changed", "Units/B.swift changed"])
}

@Test func summariesNameFilesAndCountTheRest() {
    let reasons = Reasons(
        changedFiles: ["M/A.swift", "M/B.swift", "M/C.swift"],
        changedConformances: [description, description], impactedDependencies: ["shared"])
    #expect(
        reasons.summary
            == "M/A.swift, M/B.swift, and 1 more changed; "
            + "2 conformances of types it uses came or went; "
            + "it depends on shared, which is impacted")
}

@Test func dependenciesImpactTheirDependents() {
    let dependencies = ["test": ["shared"], "shared": ["deeper"], "cycle": ["cycle"]]
    func of(_ test: String, _ own: [String: Reasons]) -> (impacted: [String], missing: [String]) {
        ImpactAnalysis.dependencies(
            of: test, dependencies: { dependencies[$0] ?? [] }, reasons: own)
    }
    let holds = Reasons()
    let changed = Reasons(changedFiles: ["X"])
    #expect(of("test", ["test": holds, "shared": holds, "deeper": holds]) == ([], []))
    #expect(of("test", ["test": holds, "shared": holds, "deeper": changed]) == (["deeper"], []))
    #expect(of("test", ["test": holds]) == ([], ["shared"]))
    #expect(of("cycle", ["cycle": holds]) == ([], []))
}
