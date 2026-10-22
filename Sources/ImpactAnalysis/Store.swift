import CryptoKit
import Foundation

/// SwiftImpact's state for one build directory, kept in it as a cache of the build:
/// `impact/recordings`, where probes save recordings, and `impact/snapshots`, where analyses
/// save what each build they saw was.
///
/// Several harnesses may use one build directory at once, such as a macOS and an iOS job. Every
/// file is written atomically, under a name of its own, and a file another harness may still
/// need is removed only once it's older than ``gracePeriod``.
struct Store {
    /// How long a file that seems unneeded is kept. Another harness may have just saved a
    /// snapshot its tests are about to record against, or be writing files in a format this
    /// version can't read.
    static let gracePeriod: TimeInterval = 60 * 60

    let directory: URL

    init(buildDirectory: URL) {
        directory = buildDirectory.standardizedFileURL.appending(path: "impact")
    }

    var recordings: URL { directory.appending(path: "recordings") }
    var snapshotsDirectory: URL { directory.appending(path: "snapshots") }

    /// Saves `snapshots`, or marks them as fresh if they're saved already.
    func save(_ snapshots: [Snapshot]) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: snapshotsDirectory, withIntermediateDirectories: true)
        for snapshot in snapshots {
            let url = snapshotsDirectory.appending(path: "\(snapshot.key).json")
            if fileManager.fileExists(atPath: url.path) {
                try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
            } else {
                try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
            }
        }
    }

    /// Every saved snapshot this version of SwiftImpact can read.
    func snapshots() -> [Snapshot] {
        files(in: snapshotsDirectory).compactMap { url in
            guard
                let snapshot = try? JSONDecoder().decode(
                    Snapshot.self, from: Data(contentsOf: url)),
                snapshot.version == Snapshot.version
            else {
                removeIfStale(url)
                return nil
            }
            return snapshot
        }
    }

    /// Removes the stale saved snapshots whose keys aren't in `keys`.
    func removeSnapshots(except keys: Set<String>) {
        for url in files(in: snapshotsDirectory)
        where !keys.contains(url.deletingPathExtension().lastPathComponent) {
            removeIfStale(url)
        }
    }

    /// Removes the file at `url` if it's older than ``gracePeriod``.
    func removeIfStale(_ url: URL, now: Date = Date()) {
        guard
            let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate,
            now.timeIntervalSince(modified) > Self.gracePeriod
        else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// The latest recording of each test, by test. Removes older recordings, and stale ones this
    /// version of SwiftImpact can't read.
    func latestRecordings() -> [String: Recording] {
        var latest: [String: (recording: Recording, url: URL)] = [:]
        for url in files(in: recordings) {
            guard
                let recording = try? JSONDecoder().decode(
                    Recording.self, from: Data(contentsOf: url)),
                recording.version == Recording.version
            else {
                removeIfStale(url)
                continue
            }
            if let previous = latest[recording.test] {
                if previous.recording.time >= recording.time {
                    try? FileManager.default.removeItem(at: url)
                    continue
                }
                try? FileManager.default.removeItem(at: previous.url)
            }
            latest[recording.test] = (recording, url)
        }
        return latest.mapValues(\.recording)
    }

    /// The JSON files in `directory`, skipping files still being written.
    func files(in directory: URL) -> [URL] {
        let urls =
            (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix(".") }
    }
}

/// What a probe saved about one test. `ImpactProbe` writes the format.
struct Recording: Decodable {
    static let version = 1

    let version: Int
    let test: String
    let declaredIn: String?
    /// The other recordings the test depends on.
    let dependsOn: [String]
    /// When it was saved, in nanoseconds since 1970.
    let time: UInt64
    /// The `LC_UUID`s of the instrumented images the test ran in.
    let images: [String]
    let functions: [UInt64]
}

/// One configuration of a build as an analysis saw it: its instrumented images, and the index of
/// its objects.
struct Snapshot: Codable, Sendable {
    static let version = 1

    var version = Self.version
    /// The configuration's directory name under `out/Products`, such as `Debug`.
    var configuration: String
    /// The sorted `LC_UUID`s of its instrumented images.
    var images: [String]
    var index: BuildIndex

    /// A name for the snapshot, from its images.
    var key: String {
        SHA256.hash(data: Data(images.joined(separator: ",").utf8)).prefix(12)
            .map { String(format: "%02x", $0) }.joined()
    }

    /// A snapshot of each configuration in the SwiftPM build in `buildDirectory` that has
    /// instrumented images.
    static func all(in buildDirectory: URL) throws -> [Snapshot] {
        let fileManager = FileManager.default
        let products = buildDirectory.appending(path: "out/Products")
        var snapshots: [Snapshot] = []
        for configuration
            in (try? fileManager.contentsOfDirectory(at: products, includingPropertiesForKeys: nil))
            ?? []
        {
            let enumerator = fileManager.enumerator(
                at: configuration, includingPropertiesForKeys: [.isRegularFileKey])
            let images = (enumerator?.compactMap { $0 as? URL } ?? []).compactMap { url in
                (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                    ? instrumentedImageUUID(at: url) : nil
            }
            guard !images.isEmpty else { continue }
            let name = configuration.lastPathComponent
            snapshots.append(
                Snapshot(
                    configuration: name, images: Set(images).sorted(),
                    index: try BuildIndex(swiftPMBuild: buildDirectory, configuration: name)))
        }
        return snapshots
    }
}
