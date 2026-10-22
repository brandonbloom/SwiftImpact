import Foundation
import ImpactCase
import ImpactProbe
import Units

// Harness <out.json> [<unit> | --parallel | --pause <milliseconds>]
//   Runs every unit in this process: in order, pausing between units if asked, or all at once on
//   threads of their own, each starting 20 ms after the one before. Or runs only `unit`. Writes what each returned and the name hashes of
//   the functions it ran.

struct Record: Encodable {
    let unit: String
    let output: String
    let functions: [UInt64]
    let sources: [String]
}

final class Records: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var all: [Record] = []

    func append(_ record: Record) {
        lock.withLock { all.append(record) }
    }
}

func measure(_ unit: ImpactCase.Unit, into records: Records) {
    let probe = try! ImpactProbe()
    let output = unit.run()
    records.append(
        Record(
            unit: unit.name, output: output, functions: probe.executed(), sources: [unit.fileID]))
}

let arguments = Array(CommandLine.arguments.dropFirst())
try ImpactProbe.check()
let records = Records()
switch arguments.dropFirst().first {
case "--parallel":
    let group = DispatchGroup()
    for (index, unit) in units.enumerated() {
        group.enter()
        Thread.detachNewThread {
            usleep(UInt32(index) * 20_000)
            measure(unit, into: records)
            group.leave()
        }
    }
    group.wait()
case "--pause":
    let pause = UInt32(arguments[2])! * 1000
    for unit in units {
        measure(unit, into: records)
        usleep(pause)
    }
case let name?:
    for unit in units where unit.name == name { measure(unit, into: records) }
case nil:
    for unit in units { measure(unit, into: records) }
}
try JSONEncoder().encode(records.all).write(to: URL(filePath: arguments[0]))
