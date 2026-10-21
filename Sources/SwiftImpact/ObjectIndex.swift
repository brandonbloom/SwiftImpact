import Foundation

/// The object files of one build: each one's fingerprint, and which one defines each instrumented
/// function.
public struct ObjectIndex: Codable, Sendable {
    /// Each object's fingerprint, by path relative to the build directory.
    public var fingerprints: [String: String]
    /// The objects that define each function, by name hash. A function defined in several is
    /// attributed to each, conservatively.
    public var owners: [UInt64: [String]]
    /// The object compiled from each source file, by the file's `#fileID` (`Module/File.swift`).
    public var sources: [String: String]
    /// The objects defining the global and static variables each object reads. See
    /// `ObjectFile.isGlobalAddressor(_:)`.
    public var globalReads: [String: [String]]
    /// Each object's protocol conformances, and the types it defines or refers to. See
    /// `ObjectFile.conformances` and `ObjectFile.types`.
    public var conformances: [String: [String]]
    public var types: [String: [String]]

    public init(
        fingerprints: [String: String] = [:], owners: [UInt64: [String]] = [:],
        sources: [String: String] = [:], globalReads: [String: [String]] = [:],
        conformances: [String: [String]] = [:], types: [String: [String]] = [:]
    ) {
        self.fingerprints = fingerprints
        self.owners = owners
        self.sources = sources
        self.globalReads = globalReads
        self.conformances = conformances
        self.types = types
    }

    /// Every conformance in the build.
    public var allConformances: Set<String> { Set(conformances.values.joined()) }

    /// Indexes `objects`, naming them relative to `root`. Each object's directory may hold a
    /// `<Module>-OutputFileMap.json`, as SwiftPM writes, which gives the source file of each.
    public init(objects: [URL], relativeTo root: URL) throws {
        self.init()
        let prefix = root.standardizedFileURL.path + "/"
        func relative(_ url: URL) -> String {
            var path = url.standardizedFileURL.path
            if path.hasPrefix(prefix) { path.removeFirst(prefix.count) }
            return path
        }
        var directories = Set<URL>()
        var addressors: [String: String] = [:]
        var reads: [String: [String]] = [:]
        for url in objects {
            let object = try ObjectFile(contentsOf: url)
            let path = relative(url)
            fingerprints[path] = object.fingerprint
            for function in object.profiledFunctions {
                owners[function, default: []].append(path)
            }
            for symbol in object.defined where ObjectFile.isGlobalAddressor(symbol) {
                addressors[symbol] = path
            }
            reads[path] = object.undefined.filter(ObjectFile.isGlobalAddressor)
            conformances[path] = object.conformances
            types[path] = object.types.sorted()
            directories.insert(url.deletingLastPathComponent())
        }
        for (path, symbols) in reads {
            let definers = Set(symbols.compactMap { addressors[$0] })
            if !definers.isEmpty { globalReads[path] = definers.sorted() }
        }
        for directory in directories {
            let maps =
                (try? FileManager.default.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: nil)) ?? []
            for map in maps where map.lastPathComponent.hasSuffix("-OutputFileMap.json") {
                let module = map.lastPathComponent.dropLast("-OutputFileMap.json".count)
                guard
                    let entries = try? JSONSerialization.jsonObject(with: Data(contentsOf: map))
                        as? [String: [String: String]]
                else { continue }
                for (source, outputs) in entries where !source.isEmpty {
                    guard let object = outputs["object"] else { continue }
                    let fileID = "\(module)/\(URL(filePath: source).lastPathComponent)"
                    sources[fileID] = relative(URL(filePath: object))
                }
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

    /// The footprint of a unit that ran `functions` and depends on the source files `sources`
    /// (`#fileID`s) whether or not it ran their code.
    ///
    /// The harness names the sources it knows a unit depends on, such as the file that declares
    /// it. Code from macro expansions, such as a `#Preview` body, isn't instrumented, so it never
    /// shows up as a function that ran.
    public func footprint(of functions: some Sequence<UInt64>, sources: [String] = [])
        -> Footprint
    {
        var footprint = Footprint()
        for source in sources {
            guard let path = self.sources[source] else {
                footprint.unattributed += 1
                continue
            }
            footprint.objects[path] = fingerprints[path]
        }
        for function in functions {
            guard let owners = owners[function] else {
                footprint.unattributed += 1
                continue
            }
            for path in owners {
                footprint.objects[path] = fingerprints[path]
            }
        }
        // A global's initializer runs once per process, so a unit that reads it may not run it.
        // Add the objects defining every global the footprint's objects read, and theirs in turn.
        var pending = Array(footprint.objects.keys)
        while let path = pending.popLast() {
            for definer in globalReads[path] ?? [] where footprint.objects[definer] == nil {
                footprint.objects[definer] = fingerprints[definer]
                pending.append(definer)
            }
        }
        footprint.types = Set(footprint.objects.keys.flatMap { types[$0] ?? [] }).sorted()
        return footprint
    }
}

/// What a set of units depended on when they ran, to compare with later builds.
public struct Ledger: Codable, Sendable {
    /// Every protocol conformance in the build the units ran in.
    public var conformances: [String]
    public var footprints: [String: Footprint]

    public init(index: ObjectIndex, footprints: [String: Footprint]) {
        conformances = index.allConformances.sorted()
        self.footprints = footprints
    }

    /// The units that may behave differently in the build `index` describes, each with why:
    /// objects in its footprint that changed, and conformances added or removed for its types.
    public func affected(in index: ObjectIndex) -> [String: [String]] {
        let changedConformances = Set(conformances).symmetricDifference(index.allConformances)
        var affected: [String: [String]] = [:]
        for (unit, footprint) in footprints {
            var reasons = footprint.changes(in: index)
            for conformance in changedConformances
            where footprint.types.contains(where: { conformance.hasPrefix($0) }) {
                reasons.append(conformance)
            }
            if !reasons.isEmpty { affected[unit] = reasons }
        }
        return affected
    }
}

/// What a unit of work depended on: each object whose code it ran, with that object's fingerprint
/// when it ran.
public struct Footprint: Codable, Sendable, Equatable {
    public var objects: [String: String] = [:]
    /// The manglings of the types its objects define or refer to. A conformance added or removed
    /// for one of them can change what it does through a runtime lookup, such as `as? P`,
    /// without changing any of its objects.
    public var types: [String] = []
    /// Functions that ran, or sources named, that no indexed object accounts for, such as ones
    /// from a stale index.
    public var unattributed = 0

    public init() {}

    /// The objects in this footprint that `index` lacks or fingerprints differently. A unit whose
    /// footprint has none can be skipped.
    public func changes(in index: ObjectIndex) -> [String] {
        objects.filter { index.fingerprints[$0.key] != $0.value }.map(\.key).sorted()
    }
}
