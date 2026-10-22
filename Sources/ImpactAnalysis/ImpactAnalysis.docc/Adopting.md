# Adopting SwiftImpact

Record what each unit runs, then select the units a later build may affect.

## Overview

Adopting SwiftImpact means changing two places: the process that runs your tests links `ImpactProbe` to record each one, and the harness that launches it uses this module to decide what to run. The harness supplies three things only it knows: what a unit is, any files a unit depends on that the probe can't see, and whether a unit passed.

### Build the process under test with instrumentation

Build every target whose code units may run with LLVM's instrumentation:

```sh
swift build -Xswiftc -profile-generate
```

The probe reads the instrumentation's counters in memory and never needs a profile file. The profiling runtime still writes one when the process exits, to `default.profraw` in its working directory, so point `LLVM_PROFILE_FILE` somewhere disposable when launching it.

### Record each unit

Link `ImpactProbe` into the process under test. Create a probe as each unit starts, and ask it what ran when the unit ends:

```swift
let probe = try ImpactProbe()
runTheUnit()
let functions = probe.executed()
```

Units can run in parallel, in one process or many. A unit's functions include whatever else ran in its process meanwhile, so units that overlap select each other's changes too; separate processes keep them apart. Before calling `executed()`, wait for any work the unit started. Send `functions` to the harness however suits it, such as a JSON file per unit.

If creating the probe throws, the process can't be measured: run the unit regardless, and show the error's description to say why. `ImpactProbe.check()` answers the same question up front.

### Resolve recordings to footprints

After the run, index the build the units ran in, and resolve each unit's recording to a ``Footprint``:

```swift
let index = try BuildIndex(swiftPMBuild: URL(filePath: ".build"))
let footprint = index.footprint(
    of: functions, sources: ["Module/DeclaringFile.swift"])
```

Name in `sources` the `#fileID` of each file the unit depends on whether or not it runs instrumented code there. At least name the file declaring the unit: code that macros generate, such as a `#Preview` body or a `@Test` function's registration, has no counters.

### Keep an impact graph

An ``ImpactGraph`` holds the footprints of the units that passed, and what it needs from the build they ran in. It's `Codable`, so the harness can store it between runs:

```swift
var graph = ImpactGraph(index: index, footprints: passed)
try JSONEncoder().encode(graph).write(to: graphURL)
```

After a later run, record the footprints of the units that passed, and forget the units that failed so they run again:

```swift
graph.record(passed, in: index)
for unit in failed {
    graph.forget(unit)
}
```

Recording keeps the footprints of units that didn't run, so a run of only the selected units leaves the graph complete.

### Select

After the next build, index it and ask the stored graph which units it affects:

```swift
let affected = graph.affected(in: try BuildIndex(swiftPMBuild: build))
for (unit, reasons) in affected {
    print(unit, reasons)  // The changed objects and conformances that selected it.
}
```

``ImpactGraph/affected(in:)`` only knows the units in the graph. Run, too:
- units the graph lacks, such as new ones and ones that last failed;
- every unit, when the environment changed (see <doc:Limitations>).
