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

func recording(images: [String] = ["U1"], functions: [UInt64] = [1]) -> Recording {
    Recording(
        version: 1, test: "t", declaredIn: "Units/A.swift", time: 0, images: images,
        functions: functions)
}

@Test func resultHoldsWhenNothingItUsedChanged() {
    let before = snapshot(images: ["U1"], fingerprints: ["A.o": "1", "B.o": "1"])
    let after = snapshot(images: ["U2"], fingerprints: ["A.o": "1", "B.o": "2"])
    #expect(ImpactAnalysis.reason(for: recording(), recordedIn: before, current: [after]) == nil)
}

@Test func changedFilesAreNamed() {
    let before = snapshot(images: ["U1"], fingerprints: ["A.o": "1", "B.o": "1"])
    let after = snapshot(images: ["U2"], fingerprints: ["A.o": "2", "B.o": "1"])
    #expect(
        ImpactAnalysis.reason(for: recording(), recordedIn: before, current: [after])
            == "Units/A.swift changed")
}

@Test func conformancesOfUsedTypesAreNamed() {
    let before = snapshot(images: ["U1"], fingerprints: ["A.o": "1", "B.o": "1"])
    let after = snapshot(
        images: ["U2"], fingerprints: ["A.o": "1", "B.o": "1"],
        conformances: ["_$s5Units3TagVs23CustomStringConvertiblesMc"])
    #expect(
        ImpactAnalysis.reason(for: recording(), recordedIn: before, current: [after])
            == "the conformance Units.Tag : Swift.CustomStringConvertible came or went")
}

@Test func unknownBuildsAndCodeMeanRunning() {
    let current = snapshot(images: ["U2"], fingerprints: ["A.o": "1", "B.o": "1"])
    #expect(
        ImpactAnalysis.reason(for: recording(), recordedIn: nil, current: [current])
            == "it was recorded in a build that wasn't analyzed")
    #expect(
        ImpactAnalysis.reason(
            for: recording(functions: [9]), recordedIn: current, current: [current])
            == "it ran code its build couldn't attribute to a file")
}

@Test func listsNameAtMostThree() {
    #expect(list(["b", "a"]) == "a and b")
    #expect(list(["d", "c", "b", "a"]) == "a, b, and 2 more")
}
