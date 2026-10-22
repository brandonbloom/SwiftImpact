import Foundation

/// A conformance case: a small package, the units it runs, and one edit to it.
///
/// A case is a directory holding `case.json` and a directory per module. The `Units` module is
/// required and declares `public let units: [Unit]`. Source files mark the edit; see
/// `render(_:for:)`.
public struct Case: Sendable {
    public let name: String
    public let manifest: Manifest
    /// The source files of each module, by module name and then file name.
    let modules: [String: [String: String]]

    /// A case's `case.json`.
    public struct Manifest: Codable, Sendable {
        /// What the edit is and what it exercises.
        public var summary: String
        /// The modules each module depends on. `Units` depends on every other module by default.
        public var dependencies: [String: [String]]?
        public var knownEscapes: [KnownEscape]?
        /// Milliseconds to wait between units in the shared mode, so work a unit leaves running
        /// finishes before the next one starts.
        public var pauseBetweenUnits: Int?
    }

    /// A unit expected to escape selection: a known gap, with why.
    public struct KnownEscape: Codable, Sendable {
        public var unit: String
        /// The modes it escapes in; every mode when absent.
        public var modes: [Mode]?
        public var reason: String
    }

    public init(contentsOf directory: URL) throws {
        name = directory.lastPathComponent
        manifest = try JSONDecoder().decode(
            Manifest.self, from: Data(contentsOf: directory.appending(path: "case.json")))
        var modules: [String: [String: String]] = [:]
        let fileManager = FileManager.default
        for module in try fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey])
        where (try? module.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            var files: [String: String] = [:]
            for file in try fileManager.contentsOfDirectory(
                at: module, includingPropertiesForKeys: nil)
            {
                files[file.lastPathComponent] = try String(contentsOf: file, encoding: .utf8)
            }
            modules[module.lastPathComponent] = files
        }
        guard modules["Units"] != nil else {
            throw CaseError(name: name, problem: "no Units module")
        }
        self.modules = modules
    }

    /// The cases in `directory`, by name.
    public static func all(in directory: URL) throws -> [Case] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { FileManager.default.fileExists(atPath: $0.appending(path: "case.json").path) }
            .map(Case.init(contentsOf:))
            .sorted { $0.name < $1.name }
    }

    /// The package's files for `side` of the edit, by path relative to the package, excluding
    /// the support files every case shares. A file whose rendering is blank is left out.
    func files(for side: Side) -> [String: String] {
        var files = ["Package.swift": manifestSource]
        for (module, sources) in modules {
            for (name, source) in sources {
                let rendered = render(source, for: side)
                if rendered.allSatisfy(\.isWhitespace) { continue }
                files["Sources/\(module)/\(name)"] = rendered
            }
        }
        return files
    }

    /// The case's `Package.swift`.
    var manifestSource: String {
        let others = modules.keys.filter { $0 != "Units" }.sorted()
        func dependencies(of module: String) -> [String] {
            manifest.dependencies?[module] ?? (module == "Units" ? others : [])
        }
        func list(_ names: [String]) -> String {
            names.map { "\"\($0)\"" }.joined(separator: ", ")
        }
        let targets = others.map {
            "        .target(name: \"\($0)\", dependencies: [\(list(dependencies(of: $0)))]),"
        }
        return """
            // swift-tools-version: 6.2

            import PackageDescription

            let package = Package(
                name: "Case",
                platforms: [.macOS("15.0")],
                targets: [
                    .target(name: "ImpactProbe"),
                    .target(name: "ImpactCase"),
            \(targets.joined(separator: "\n"))
                    .target(
                        name: "Units",
                        dependencies: [\(list(["ImpactCase"] + dependencies(of: "Units")))]),
                    .executableTarget(
                        name: "Harness", dependencies: ["ImpactProbe", "ImpactCase", "Units"]),
                ]
            )

            """
    }
}

struct CaseError: Error, CustomStringConvertible {
    let name: String
    let problem: String
    var description: String { "\(name): \(problem)" }
}
