import Testing

@testable import ImpactAnalysis

/// A snapshot of a build of `Units/A.swift` and `Units/B.swift`, whose functions 1 and 2 they
/// define, with `fingerprints` and `conformances`.
func snapshot(
    images: [String], fingerprints: [String: String], conformances: [String] = []
) -> Snapshot {
    Snapshot(
        configuration: "Debug", images: images,
        index: BuildIndex(
            fingerprints: fingerprints, owners: [1: ["A.o"], 2: ["B.o"]],
            sources: ["Units/A.swift": "A.o", "Units/B.swift": "B.o"],
            conformances: ["B.o": conformances], types: ["A.o": ["_$s5Units3TagV"]]))
}

func recording(
    images: [String] = ["U1"], functions: [UInt64] = [1], declaredIn: String? = "Units/A.swift"
) -> Recording {
    Recording(
        version: 1, test: "t", declaredIn: declaredIn, dependsOn: [], time: 0, images: images,
        functions: functions)
}

@Test func testsWithoutRecordingsAreImpacted() {
    let analysis = ImpactAnalysis(
        reasons: ["recorded": [], "changed": ["Units/A.swift changed"]], recordedTestCount: 2)
    #expect(!analysis.isImpacted("recorded"))
    #expect(analysis.isImpacted("changed"))
    #expect(analysis.isImpacted("unknown"))
    #expect(analysis.explain("recorded") == "its last result still holds")
    #expect(analysis.explain("changed") == "Units/A.swift changed")
    #expect(analysis.explain("unknown") == "it has no recording")
}

@Test func resultHoldsWhenNothingItUsedChanged() {
    let before = snapshot(images: ["U1"], fingerprints: ["A.o": "1", "B.o": "1"])
    let after = snapshot(images: ["U2"], fingerprints: ["A.o": "1", "B.o": "2"])
    #expect(
        ImpactAnalysis.assess(recording(), recordedIn: before, current: [after]).reasons.isEmpty)
}

@Test func changedFilesAreNamed() {
    let before = snapshot(images: ["U1"], fingerprints: ["A.o": "1", "B.o": "1"])
    let after = snapshot(images: ["U2"], fingerprints: ["A.o": "2", "B.o": "1"])
    #expect(
        ImpactAnalysis.assess(recording(), recordedIn: before, current: [after]).reasons
            == ["Units/A.swift changed"])
}

@Test func conformancesOfUsedTypesAreNamed() {
    let before = snapshot(images: ["U1"], fingerprints: ["A.o": "1", "B.o": "1"])
    let after = snapshot(
        images: ["U2"], fingerprints: ["A.o": "1", "B.o": "1"],
        conformances: ["_$s5Units3TagVs23CustomStringConvertiblesMc"])
    #expect(
        ImpactAnalysis.assess(recording(), recordedIn: before, current: [after]).reasons
            == ["the conformance Units.Tag : Swift.CustomStringConvertible came or went"])
}

@Test func unknownBuildsAndCodeMeanRunning() {
    let current = snapshot(images: ["U2"], fingerprints: ["A.o": "1", "B.o": "1"])
    let unanalyzed = ImpactAnalysis.assess(recording(), recordedIn: nil, current: [current])
    #expect(!unanalyzed.usable)
    #expect(unanalyzed.reasons == ["it was recorded in a build that wasn't analyzed"])
    let unattributed = ImpactAnalysis.assess(
        recording(functions: [9]), recordedIn: current, current: [current])
    #expect(!unattributed.usable)
    #expect(unattributed.reasons == ["it ran code its build couldn't attribute to a file"])
    #expect(ImpactAnalysis.assess(recording(), recordedIn: current, current: [current]).usable)
}

@Test func theDeclaringFileCountsOnlyWhenKnown() {
    let before = snapshot(images: ["U1"], fingerprints: ["A.o": "1", "B.o": "1"])
    let after = snapshot(images: ["U2"], fingerprints: ["A.o": "2", "B.o": "1"])
    let declared = recording(functions: [2])
    let undeclared = recording(functions: [2], declaredIn: nil)
    #expect(
        ImpactAnalysis.assess(declared, recordedIn: before, current: [after]).reasons
            == ["Units/A.swift changed"])
    #expect(ImpactAnalysis.assess(undeclared, recordedIn: before, current: [after]).reasons.isEmpty)
}

@Test func eachChangedFileIsAReasonOfItsOwn() {
    let before = snapshot(images: ["U1"], fingerprints: ["A.o": "1", "B.o": "1"])
    let after = snapshot(images: ["U2"], fingerprints: ["A.o": "2", "B.o": "2"])
    #expect(
        ImpactAnalysis.assess(
            recording(functions: [1, 2]), recordedIn: before, current: [after]
        ).reasons
            == ["Units/A.swift changed", "Units/B.swift changed"])
}

@Test func dependenciesImpactTheirDependents() {
    let dependencies = ["test": ["shared"], "shared": ["deeper"], "cycle": ["cycle"]]
    func reasons(_ test: String, _ own: [String: [String]]) -> [String] {
        ImpactAnalysis.dependencyReasons(
            of: test, dependencies: { dependencies[$0] ?? [] }, reasons: own)
    }
    #expect(reasons("test", ["test": [], "shared": [], "deeper": []]).isEmpty)
    #expect(
        reasons("test", ["test": [], "shared": [], "deeper": ["X changed"]])
            == ["it depends on deeper, which is impacted"])
    #expect(reasons("test", ["test": []]) == ["it depends on shared, which has no recording"])
    #expect(reasons("cycle", ["cycle": []]).isEmpty)
}
