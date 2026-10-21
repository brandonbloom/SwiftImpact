import Foundation
import ImpactCase
import ImpactProbe
import Units

// Harness <out.json> [unit]
//   Runs every unit in this process, in order, or only `unit`. Writes what each returned and the
//   name hashes of the functions it ran.

struct Record: Encodable {
    let unit: String
    let output: String
    let functions: [UInt64]
    let sources: [String]
}

let arguments = CommandLine.arguments
try ImpactProbe.check()
let chosen = arguments.count > 2 ? units.filter { $0.name == arguments[2] } : units
var records: [Record] = []
for unit in chosen {
    ImpactProbe.reset()
    let output = unit.run()
    records.append(
        Record(
            unit: unit.name, output: output, functions: ImpactProbe.executed(),
            sources: [unit.fileID]))
}
try JSONEncoder().encode(records).write(to: URL(filePath: arguments[1]))
