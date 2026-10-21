import Foundation
import SwiftImpact

/// A case's package on disk, built instrumented, with the units' harness.
struct Workspace {
    let directory: URL
    /// The files every case's package shares, by path relative to the package.
    let support: [String: String]

    var buildDirectory: URL { directory.appending(path: ".build") }

    /// Writes `testCase`'s package for `side`. Only files whose contents differ are written, and
    /// files the side lacks are removed, so a build after it is incremental.
    func write(_ testCase: Case, for side: Side) throws {
        let fileManager = FileManager.default
        let files = support.merging(testCase.files(for: side)) { $1 }
        for (path, contents) in files {
            let url = directory.appending(path: path)
            if (try? String(contentsOf: url, encoding: .utf8)) == contents { continue }
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: false, encoding: .utf8)
        }
        let sources = directory.appending(path: "Sources")
        let enumerator = fileManager.enumerator(at: sources, includingPropertiesForKeys: nil)
        let prefix = directory.standardizedFileURL.path + "/"
        for case let url as URL in enumerator?.allObjects ?? [] {
            let path = String(url.standardizedFileURL.path.dropFirst(prefix.count))
            if !url.hasDirectoryPath, files[path] == nil { try fileManager.removeItem(at: url) }
        }
    }

    /// Builds the harness with `-profile-generate`, and returns its path.
    func build() throws -> URL {
        try command(
            "swift", "build", "--product", "Harness", "-Xswiftc", "-profile-generate",
            in: directory)
        let binPath = try command("swift", "build", "--show-bin-path", in: directory)
        return URL(filePath: binPath.trimmingCharacters(in: .whitespacesAndNewlines))
            .appending(path: "Harness")
    }

    /// Removes the build, so the next one is clean.
    func clean() throws {
        try FileManager.default.removeItem(at: buildDirectory)
    }

    func index() throws -> ObjectIndex {
        try ObjectIndex(
            objects: ObjectIndex.swiftPMObjects(in: buildDirectory), relativeTo: buildDirectory)
    }

    /// What one unit returned in a run, and what it ran.
    struct Record: Decodable {
        let unit: String
        let output: String
        let functions: [UInt64]
        let sources: [String]
    }

    /// Runs every unit in one process, or only `unit`, with the harness at `harness`.
    func run(_ harness: URL, unit: String? = nil) throws -> [Record] {
        let out = directory.appending(path: "records.json")
        var arguments = [harness.path, out.path]
        if let unit { arguments.append(unit) }
        try command(
            arguments, in: directory,
            environment: ["LLVM_PROFILE_FILE": directory.appending(path: "default.profraw").path])
        return try JSONDecoder().decode([Record].self, from: Data(contentsOf: out))
    }
}
