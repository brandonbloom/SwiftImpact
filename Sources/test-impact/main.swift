import Foundation
import TestImpact

// test-impact footprints <build-dir> <recordings-dir> <footprints.json>
//   Indexes the build's objects and resolves each recording, a JSON file of
//   {"unit": String, "functions": [UInt64], "sources": [String]?} that ImpactProbe's user wrote,
//   to a footprint.
// test-impact select <build-dir> <footprints.json>
//   Prints each unit whose footprint changed in the build, and why, then a summary.

func index(_ build: String) throws -> ObjectIndex {
  let root = URL(filePath: build, directoryHint: .isDirectory)
  return try ObjectIndex(objects: ObjectIndex.swiftPMObjects(in: root), relativeTo: root)
}

struct Recording: Decodable {
  let unit: String
  let functions: [UInt64]
  var sources: [String]? = nil
}

let arguments = CommandLine.arguments.dropFirst()
switch (arguments.first, arguments.count) {
case ("fingerprint", _):
  for path in arguments.dropFirst() {
    let index = try ObjectIndex(objects: [URL(filePath: path)], relativeTo: URL(filePath: "/"))
    print(index.fingerprints.first!.value, path)
  }
case ("footprints", 4):
  let args = Array(arguments)
  let index = try index(args[1])
  var footprints: [String: Footprint] = [:]
  let recordings = try FileManager.default.contentsOfDirectory(
    at: URL(filePath: args[2]), includingPropertiesForKeys: nil)
  for url in recordings where url.pathExtension == "json" {
    let recording = try JSONDecoder().decode(Recording.self, from: Data(contentsOf: url))
    footprints[recording.unit] = index.footprint(
      of: recording.functions, sources: recording.sources ?? [])
  }
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  try encoder.encode(Ledger(index: index, footprints: footprints))
    .write(to: URL(filePath: args[3]))
  let sizes = footprints.values.map(\.objects.count).sorted()
  print(
    "\(footprints.count) footprints from \(index.fingerprints.count) objects; objects per unit: "
      + "min \(sizes.first ?? 0), median \(sizes.isEmpty ? 0 : sizes[sizes.count / 2]), max \(sizes.last ?? 0); "
      + "unattributed functions: \(footprints.values.map(\.unattributed).reduce(0, +))")
case ("select", 3):
  let args = Array(arguments)
  let index = try index(args[1])
  let ledger = try JSONDecoder().decode(
    Ledger.self, from: Data(contentsOf: URL(filePath: args[2])))
  let affected = ledger.affected(in: index)
  for (unit, reasons) in affected.sorted(by: { $0.key < $1.key }) {
    let short = reasons.map { ($0 as NSString).lastPathComponent }
    print("\(unit)\t\(short.joined(separator: " "))")
  }
  print("selected \(affected.count) of \(ledger.footprints.count)")
default:
  FileHandle.standardError.write(
    Data(
      "usage: test-impact footprints <build> <recordings> <out> | select <build> <footprints>\n"
        .utf8))
  exit(2)
}
