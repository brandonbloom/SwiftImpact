# SwiftImpact

Skip tests a change can't affect, for Swift.

> **Spike.** Built to measure the approach with SwiftBook, its first consumer. See SwiftBook's `docs/spikes/swift-impact.md` for the design, the results, and the known gaps.

A unit of work, such as a test or a snapshot render, runs in a process built with `-profile-generate`. `ImpactProbe` records which functions it runs. `SwiftImpact` maps those functions to the per-source-file objects of a SwiftPM build and fingerprints the objects. A later build can then tell which units it may change:
- units whose objects changed;
- units that read globals defined in changed objects;
- units that use types whose protocol conformances came or went.

```swift
// In the process under test, around each unit:
try ImpactProbe.check()
ImpactProbe.reset()
runTheUnit()
let functions = ImpactProbe.executed()

// In the harness, after the run:
let index = try ObjectIndex(objects: ObjectIndex.swiftPMObjects(in: build), relativeTo: build)
let footprint = index.footprint(of: functions, sources: ["Module/DeclaringFile.swift"])
let ledger = Ledger(index: index, footprints: [unit: footprint])

// Before the next run:
let affected = ledger.affected(in: try ObjectIndex(objects: …, relativeTo: build))
```

Counters are per process, so measure one unit at a time.
