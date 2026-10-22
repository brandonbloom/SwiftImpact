import Foundation
import PackagePlugin

/// `swift package docs [--hosting-base-path <path>]`: builds the documentation of each library's
/// modules, and merges it into one archive. Serve the archive's directory over HTTP to browse it.
///
/// With `--hosting-base-path`, the archive is made for a static host serving it under that path,
/// such as `/SwiftImpact` on GitHub Pages, and its root redirects to the documentation.
@main struct Docs: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        var extractor = ArgumentExtractor(arguments)
        let hostingBasePath = extractor.extractOption(named: "hosting-base-path").last
        let docc = try context.tool(named: "docc").url
        let output = context.pluginWorkDirectoryURL
        var modules: [SwiftSourceModuleTarget] = []
        for product in context.package.products(ofType: LibraryProduct.self) {
            for case let module as SwiftSourceModuleTarget in product.targets
            where !modules.contains(where: { $0.id == module.id }) {
                modules.append(module)
            }
        }
        var archives: [String] = []
        try FileManager.default.createDirectory(
            at: output.appending(path: "modules"), withIntermediateDirectories: true)
        for module in modules {
            let graphs = try packageManager.getSymbolGraph(
                for: module, options: .init(minimumAccessLevel: .public))
            let archive = output.appending(path: "modules/\(module.name).doccarchive")
            try? FileManager.default.removeItem(at: archive)
            var arguments = [
                "convert", "--additional-symbol-graph-dir", graphs.directoryURL.path,
                "--output-dir", archive.path, "--fallback-display-name", module.name,
                "--fallback-bundle-identifier", module.name, "--warnings-as-errors",
            ]
            let catalog = module.directoryURL.appending(path: "\(module.name).docc")
            if FileManager.default.fileExists(atPath: catalog.path) {
                arguments.insert(catalog.path, at: 1)
            }
            try run(docc, arguments)
            archives.append(archive.path)
        }
        let combined = output.appending(path: "\(context.package.displayName).doccarchive")
        try? FileManager.default.removeItem(at: combined)
        try run(
            docc,
            ["merge"] + archives + [
                "--output-path", combined.path,
                "--synthesized-landing-page-name", context.package.displayName,
            ])
        if let hostingBasePath {
            try run(
                docc,
                [
                    "process-archive", "transform-for-static-hosting", combined.path,
                    "--hosting-base-path", hostingBasePath,
                ])
            try #"<meta http-equiv="refresh" content="0; url=documentation/">"#
                .write(
                    to: combined.appending(path: "index.html"), atomically: true, encoding: .utf8)
        }
        print("Built \(combined.path)")
        print("Browse it with: python3 -m http.server --directory '\(combined.path)'")
    }

    func run(_ tool: URL, _ arguments: [String]) throws {
        let process = try Process.run(tool, arguments: arguments)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw DocsError(
                description: "docc \(arguments[0]) exited with \(process.terminationStatus)")
        }
    }
}

struct DocsError: Error, CustomStringConvertible {
    let description: String
}
