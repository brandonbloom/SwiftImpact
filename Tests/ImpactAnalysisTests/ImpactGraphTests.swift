import Testing

@testable import ImpactAnalysis

@Test func affectedListsChangedObjectsAndConformances() {
    var tagged = Footprint()
    tagged.objects = ["Tag.o": "1"]
    tagged.types = ["4Main3TagV"]
    var other = Footprint()
    other.objects = ["Other.o": "1"]
    let before = BuildIndex(fingerprints: ["Tag.o": "1", "Other.o": "1"])
    let graph = ImpactGraph(index: before, footprints: ["tagged": tagged, "other": other])
    let after = BuildIndex(
        fingerprints: ["Tag.o": "1", "Other.o": "2"],
        conformances: ["Description.o": ["4Main3TagVs23CustomStringConvertiblesMc"]])
    #expect(
        graph.affected(in: after) == [
            "tagged": ["4Main3TagVs23CustomStringConvertiblesMc"], "other": ["Other.o"],
        ])
}

@Test func recordKeepsUnitsThatDidNotRun() {
    var footprint = Footprint()
    footprint.objects = ["A.o": "1"]
    let index = BuildIndex(fingerprints: ["A.o": "1"])
    var graph = ImpactGraph(index: index, footprints: ["a": footprint, "b": footprint])
    var rerun = footprint
    rerun.objects = ["A.o": "2"]
    graph.record(["a": rerun], in: BuildIndex(fingerprints: ["A.o": "2"]))
    #expect(graph.footprints == ["a": rerun, "b": footprint])
}

@Test func recordForgetsUnitsWhoseConformancesChanged() {
    var tagged = Footprint()
    tagged.types = ["4Main3TagV"]
    var graph = ImpactGraph(
        index: BuildIndex(), footprints: ["tagged": tagged, "plain": Footprint()])
    graph.record(
        [:], in: BuildIndex(conformances: ["X.o": ["4Main3TagVs23CustomStringConvertiblesMc"]]))
    #expect(graph.footprints == ["plain": Footprint()])
}

@Test func forgetRemovesAUnit() {
    var graph = ImpactGraph(index: BuildIndex(), footprints: ["a": Footprint()])
    graph.forget("a")
    #expect(graph.footprints.isEmpty)
}
