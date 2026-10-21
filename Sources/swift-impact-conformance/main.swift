import Foundation
import ImpactConformance

// swift-impact-conformance [--no-clean-check] [<case>...]
//   Runs the named cases, or every case, with the `swift` on PATH. Records their results in
//   Conformance/Results/<environment>.json and regenerates docs/compatibility.md. Exits nonzero
//   if a unit escaped selection unexpectedly, a known gap closed, or a build diverged.

let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()
var arguments = Array(CommandLine.arguments.dropFirst())
var runner = Runner(root: root, workDirectory: root.appending(path: ".build/conformance"))
if let index = arguments.firstIndex(of: "--no-clean-check") {
    runner.checksCleanBuild = false
    arguments.remove(at: index)
}

let cases = try Case.all(in: root.appending(path: "Conformance/Cases"))
let unknown = Set(arguments).subtracting(cases.map(\.name))
guard unknown.isEmpty else {
    FileHandle.standardError.write(
        Data("unknown cases: \(unknown.sorted().joined(separator: ", "))\n".utf8))
    exit(2)
}

let environment = try Environment.current()
let resultsDirectory = root.appending(path: "Conformance/Results")
let resultsURL = resultsDirectory.appending(path: "\(environment.id).json")
var results = (try? Results(contentsOf: resultsURL)) ?? Results()
results.cases = results.cases.filter { name, _ in cases.contains { $0.name == name } }

var failed = false
for testCase in cases where arguments.isEmpty || arguments.contains(testCase.name) {
    print(testCase.name, terminator: "")
    do {
        let result = try runner.run(testCase)
        results.cases[testCase.name] = result
        try results.write(to: resultsURL)
        for mode in Mode.allCases {
            let verdict = Verdict(result.units[mode]!, mode: mode, manifest: testCase.manifest)
            print(
                "  \(mode.rawValue): \(verdict.changed) changed, \(verdict.selected) selected of "
                    + "\(verdict.units)", terminator: "")
            if !verdict.escapes.isEmpty { print(", ESCAPED: \(verdict.escapes)", terminator: "") }
            if !verdict.stale.isEmpty {
                print(", NO LONGER ESCAPE: \(verdict.stale)", terminator: "")
            }
            failed = failed || !verdict.passed
        }
        if !result.divergent.isEmpty {
            print("  DIVERGED: \(result.divergent)", terminator: "")
            failed = true
        }
        print()
    } catch {
        print("  ERROR: \(error)")
        failed = true
    }
}

var allResults: [String: Results] = [:]
for url in try FileManager.default.contentsOfDirectory(
    at: resultsDirectory, includingPropertiesForKeys: nil)
where url.pathExtension == "json" {
    allResults[url.deletingPathExtension().lastPathComponent] = try Results(contentsOf: url)
}
try compatibilityTable(cases: cases, results: allResults)
    .write(to: root.appending(path: "docs/compatibility.md"), atomically: true, encoding: .utf8)
exit(failed ? 1 : 0)
