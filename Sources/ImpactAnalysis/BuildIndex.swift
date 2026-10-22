import Foundation

/// The object files of one build: each one's fingerprint, and which one defines each instrumented
/// function.
public struct BuildIndex: Sendable {
    /// Each object's fingerprint, by path relative to the build directory.
    package private(set) var fingerprints: [String: String]
    /// The objects that define each function, by name hash. A function defined in several is
    /// attributed to each, conservatively.
    var owners: [UInt64: [String]]
    /// The object compiled from each source file, by the file's `#fileID` (`Module/File.swift`).
    var sources: [String: String]
    /// The objects defining the global and static variables each object reads through their
    /// addressors (`…vau`, `…vauZ`).
    var globalReads: [String: [String]]
    /// The protocol conformance descriptors (`…Mc`) each object defines.
    var conformances: [String: [String]]
    /// The manglings of the types each object defines or refers to.
    var types: [String: [String]]

    /// Creates an index from its parts, as a test might.
    init(
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
    var allConformances: Set<String> { Set(conformances.values.joined()) }

    /// Indexes the SwiftPM build in `buildDirectory`, such as `.build`.
    public init(swiftPMBuild buildDirectory: URL) throws {
        try self.init(objects: Self.swiftPMObjects(in: buildDirectory), relativeTo: buildDirectory)
    }

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
    static func swiftPMObjects(in buildDirectory: URL) -> [URL] {
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
