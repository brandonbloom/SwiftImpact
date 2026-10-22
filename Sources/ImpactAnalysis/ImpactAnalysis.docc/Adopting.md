# Adopting SwiftImpact

Teach your test harness to skip the tests a change can't affect.

## Overview

SwiftImpact answers one question for your harness: *does this test's last result still hold for the code as it's built now?* It records what each test runs, and compares that with each new build.

You change two places:
- **The process that runs your tests** records each test. It links `ImpactProbe`.
- **Your harness** builds, asks which tests need to run, and runs them. It uses `ImpactAnalysis`.

They can be the same process.

### Identify your tests

SwiftImpact keeps track of tests by an identifier you choose: any string, as long as it's the same from run to run. Include anything that changes what the test does. If a snapshot test renders on several devices, `"CardView/iPhone"` and `"CardView/iPad"` are different tests.

### Build for recording

SwiftImpact learns what a test runs from counters the compiler adds on request. Add ``ImpactAnalysis/ImpactAnalysis/buildArguments`` to whichever `swift build` or `swift test` builds the code your tests run, such as your own package, or one your harness generates and builds with `--package-path`:

```swift
let arguments = ["build", "--scratch-path", ".build/impact"] + ImpactAnalysis.buildArguments
```

Give these builds a scratch path of their own, as above; otherwise switching the arguments on and off rebuilds everything. The scratch path is the build directory you'll analyze.

### Record each test

In the process that runs your tests, record each test from start to finish:

```swift
import ImpactProbe

let probe = ImpactProbe.start(test: test.id, declaredIn: test.fileID)
test.run()
probe.stop()
```

- **`declaredIn`** is the `#fileID` of the file declaring the test, such as `"MyModule/ParserTests.swift"`. Code that macros generate, like a `#Preview` body, isn't counted, so SwiftImpact relies on you for it. In Swift Testing, it's `Test.current?.sourceLocation.fileID`. If you don't know it, pass `nil`: the test is still recorded, but code macros generate in its file isn't.
- **Wait for the test's work to finish before stopping,** including work on other threads. What runs after `stop()` isn't recorded.
- **Tests can run in parallel.** A recording includes everything that ran in its process meanwhile, so overlapping tests each pick up the others' dependencies. That runs some tests needlessly, never too few. Separate processes keep them apart.

Recordings are saved in the build directory, where your harness finds them. Probes record nothing unless the process was launched as the next section describes, so the same test code runs normally everywhere else.

### Record work shared across tests

Some work is done once per process and reused by several tests, such as a context computed the first time a test needs it and then cached. It runs inside at most one test's recording, so the others don't record depending on it. Record it under an identifier of its own, and name that identifier when starting each test that uses it:

```swift
// Where the shared work is done, once per process:
let shared = ImpactProbe.start(test: "shared/SampleLibrary", declaredIn: #fileID)
let library = makeSampleLibrary()
shared.stop()

// For each test that uses it:
let probe = ImpactProbe.start(
    test: test.id, declaredIn: test.fileID, dependsOn: ["shared/SampleLibrary"])
```

A test is impacted whenever a recording it depends on is, or when that recording doesn't exist yet.

Record the shared work on its own, outside any test, and make it do the same work whichever test asks for it first. Each process records it again and only the latest recording counts, so code it runs only for some tests would be missing whenever another test triggered it.

### Run what needs running

In your harness, after building, analyze the build and ask about each test:

```swift
import ImpactAnalysis

let build = URL(filePath: ".build/impact")
let analysis = try ImpactAnalysis.analyze(build)

let toRun = allTests.filter { analysis.isImpacted($0.id) }
```

To show people why a test ran, or didn't, ask the analysis to ``ImpactAnalysis/ImpactAnalysis/explain(_:)`` it, such as `"MyModule/Parser.swift changed"`. The wording is for display and may change, so don't parse it.

Then launch the process that runs your tests with ``ImpactAnalysis/ImpactAnalysis/environment(for:)`` added to its environment, so its recordings are saved where the next analysis looks:

```swift
process.environment = ProcessInfo.processInfo.environment
    .merging(ImpactAnalysis.environment(for: build)) { $1 }
```

#### Simulators

Tests that run in the iOS simulator work the same way. Build them into the same scratch path with `--triple` and `--sdk`; each platform's build is kept and analyzed separately, so one build directory serves them all. A simulator shares the host's file system, so recordings land in the build directory as usual. When you launch the process with `xcrun simctl`, it passes on only the host variables prefixed with `SIMCTL_CHILD_`, so prefix each:

```swift
let environment = ImpactAnalysis.environment(for: build)
    .map { ("SIMCTL_CHILD_\($0.key)", $0.value) }
```

#### Several harnesses at once

Several harnesses can share one build directory, such as a macOS job and an iOS job running at the same time from one checkout. SwiftPM builds into it one at a time, and SwiftImpact writes each file atomically, under a name of its own.

Analyze before every run. Each analysis takes stock of the build its run is about to use, which is what lets the next one make sense of that run's recordings.

### Add what only your harness knows

SwiftImpact compares builds, so it can only say whether what a test runs has changed. A test's result can change for other reasons your harness knows about, and it should run the test for those too:
- **Failures.** A test that isn't impacted has a last result that still holds, whether it passed or failed. If your harness keeps results, it can report the last one; if it doesn't, run the tests that failed last time.
- **Inputs outside the build.** A snapshot test's reference image, a golden file, or a fixture can change without any code changing, and so can the test's result. Keep a fingerprint of each test's inputs, such as a hash of its reference image, and run the test when it differs from the last run's.

For example, a snapshot harness that keeps each test's last result and reference hash in `lastRun` might decide:

```swift
let shouldRun =
    analysis.isImpacted(test.id)
    || lastRun[test.id]?.passed != true
    || lastRun[test.id]?.referenceHash != referenceHash(of: test)
```

### When something goes wrong

SwiftImpact fails toward running tests:
- A test it has never seen, or whose recording it can't make sense of, is impacted.
- Clearing the build directory clears SwiftImpact's state too, and every test runs.
- If ``ImpactAnalysis/ImpactAnalysis/analyze(_:)`` throws, run every test, and show the error to say why.
- If the process under test isn't built for recording, recording does nothing, and its tests run next time. A probe that can't record in a process launched for recording says why on standard error.

### Keep running everything somewhere

SwiftImpact can't see some kinds of change, such as to resources and to code that isn't instrumented; <doc:Limitations> lists them. Keep a full run, such as in CI before merging, to catch what it can't.
