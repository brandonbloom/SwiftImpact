import Foundation
import ImpactCase
import ImpactProbe
import Units

// Harness <out.json> shared [<pause milliseconds>]
// Harness <out.json> isolated <unit>
// Harness <out.json> parallel
//   Runs every unit in this process, in order, pausing between units if asked; or only `unit`;
//   or every unit at once on threads of their own, each starting 20 ms after the one before.
//   Records each unit as the test `<unit>@<mode>`, and writes what each returned.

struct Output: Encodable {
    let unit: String
    let output: String
}

final class Outputs: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var all: [Output] = []

    func append(_ output: Output) {
        lock.withLock { all.append(output) }
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
let mode = arguments[1]
let outputs = Outputs()

func run(_ unit: ImpactCase.Unit) {
    let probe = ImpactProbe.start(
        test: "\(unit.name)@\(mode)", declaredIn: unit.fileID, dependsOn: unit.dependsOn)
    let output = unit.run()
    probe.stop()
    outputs.append(Output(unit: unit.name, output: output))
}

switch mode {
case "shared":
    let pause = arguments.count > 2 ? UInt32(arguments[2])! * 1000 : 0
    for unit in units {
        run(unit)
        usleep(pause)
    }
case "isolated":
    for unit in units where unit.name == arguments[2] { run(unit) }
case "parallel":
    let group = DispatchGroup()
    for (index, unit) in units.enumerated() {
        group.enter()
        Thread.detachNewThread {
            usleep(UInt32(index) * 20_000)
            run(unit)
            group.leave()
        }
    }
    group.wait()
default:
    fatalError("unknown mode \(mode)")
}
try JSONEncoder().encode(outputs.all).write(to: URL(filePath: arguments[0]))
