import Foundation

/// The object files of one build: each one's fingerprint, and which one defines each instrumented
/// function.
public struct ObjectIndex: Codable, Sendable {
    /// Each object's fingerprint, by path relative to the build directory.
    public var fingerprints: [String: String]
    /// The objects that define each function, by name hash. A function defined in several is
    /// attributed to each, conservatively.
    public var owners: [UInt64: [String]]

    public init(fingerprints: [String: String] = [:], owners: [UInt64: [String]] = [:]) {
        self.fingerprints = fingerprints
        self.owners = owners
    }

    /// Indexes `objects`, naming them relative to `root`.
    public init(objects: [URL], relativeTo root: URL) throws {
        self.init()
        let prefix = root.standardizedFileURL.path + "/"
        for url in objects {
            let object = try ObjectFile(contentsOf: url)
            var path = url.standardizedFileURL.path
            if path.hasPrefix(prefix) { path.removeFirst(prefix.count) }
            fingerprints[path] = object.fingerprint
            for function in object.profiledFunctions {
                owners[function, default: []].append(path)
            }
        }
    }

    /// The per-source-file objects of a SwiftPM build in `buildDirectory`, such as `.build`.
    ///
    /// SwiftPM links each module through one prelinked object, but compiles each source file to
    /// an object of its own under `out/Intermediates.noindex`. Those are what this returns.
    public static func swiftPMObjects(in buildDirectory: URL) -> [URL] {
        let intermediates = buildDirectory.appending(path: "out/Intermediates.noindex")
        guard
            let enumerator = FileManager.default.enumerator(
                at: intermediates, includingPropertiesForKeys: nil)
        else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter {
            $0.pathExtension == "o" && $0.path.contains("/Objects-normal/")
        }
    }

    /// The footprint of a unit that ran `functions`.
    public func footprint(of functions: some Sequence<UInt64>) -> Footprint {
        var footprint = Footprint()
        for function in functions {
            guard let owners = owners[function] else {
                footprint.unattributed += 1
                continue
            }
            for path in owners {
                footprint.objects[path] = fingerprints[path]
            }
        }
        return footprint
    }
}

/// What a unit of work depended on: each object whose code it ran, with that object's fingerprint
/// when it ran.
public struct Footprint: Codable, Sendable, Equatable {
    public var objects: [String: String] = [:]
    /// Functions that ran but no indexed object defines, such as ones from a stale index.
    public var unattributed = 0

    public init() {}

    /// The objects in this footprint that `index` lacks or fingerprints differently. A unit whose
    /// footprint has none can be skipped.
    public func changes(in index: ObjectIndex) -> [String] {
        objects.filter { index.fingerprints[$0.key] != $0.value }.map(\.key).sorted()
    }
}
