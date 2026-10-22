import Foundation
import Testing

@testable import ImpactAnalysis

@Test func onlyStaleFilesAreRemoved() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = Store(buildDirectory: directory)
    try FileManager.default.createDirectory(
        at: store.snapshotsDirectory, withIntermediateDirectories: true)
    let fresh = store.snapshotsDirectory.appending(path: "fresh.json")
    let stale = store.snapshotsDirectory.appending(path: "stale.json")
    let needed = store.snapshotsDirectory.appending(path: "needed.json")
    for url in [fresh, stale, needed] {
        try Data("{}".utf8).write(to: url)
    }
    let old = Date(timeIntervalSinceNow: -2 * Store.gracePeriod)
    for url in [stale, needed] {
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path)
    }
    store.removeSnapshots(except: ["needed"])
    #expect(FileManager.default.fileExists(atPath: fresh.path))
    #expect(!FileManager.default.fileExists(atPath: stale.path))
    #expect(FileManager.default.fileExists(atPath: needed.path))
    try FileManager.default.removeItem(at: directory)
}
