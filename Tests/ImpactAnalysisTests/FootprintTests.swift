import Testing

@testable import ImpactAnalysis

@Test func changesListsChangedAndMissingObjects() {
    var footprint = Footprint()
    footprint.objects = ["A.o": "1", "B.o": "2", "C.o": "3"]
    let index = BuildIndex(fingerprints: ["A.o": "1", "B.o": "changed"])
    #expect(footprint.changes(in: index) == ["B.o", "C.o"])
}

@Test func functionsInSeveralObjectsDependOnEach() {
    let index = BuildIndex(
        fingerprints: ["A.o": "1", "B.o": "2"], owners: [7: ["A.o", "B.o"]])
    let footprint = index.footprint(of: [7, 8])
    #expect(footprint.objects == ["A.o": "1", "B.o": "2"])
    #expect(footprint.unattributed == 1)
}
