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

SwiftImpact learns what a test runs from counters the compiler adds on request. Add ``ImpactAnalysis/ImpactAnalysis/buildArguments`` when building the code under test:

```swift
let arguments = ["build", "--scratch-path", ".build/impact"] + ImpactAnalysis.buildArguments
```

Give these builds a scratch path of their own, as above; otherwise switching the arguments on and off rebuilds everything.

### Record each test

In the process that runs your tests, record each test from start to finish:

```swift
import ImpactProbe

let probe = ImpactProbe.start(test: test.id, declaredIn: test.fileID)
test.run()
probe.stop()
```

- **`declaredIn`** is the `#fileID` of the file declaring the test, such as `"MyModule/ParserTests.swift"`. Code that macros generate, like a `#Preview` body, isn't counted, so SwiftImpact relies on you for it. In Swift Testing, it's `Test.current?.sourceLocation.fileID`.
- **Wait for the test's work to finish before stopping,** including work on other threads. What runs after `stop()` isn't recorded.
- **Tests can run in parallel.** A recording includes everything that ran in its process meanwhile, so overlapping tests each pick up the others' dependencies. That runs some tests needlessly, never too few. Separate processes keep them apart.

Recordings are saved in the build directory, where your harness finds them. Probes record nothing unless the process was launched as the next section describes, so the same test code runs normally everywhere else.

### Run what needs running

In your harness, after building, analyze the build and ask about each test:

```swift
import ImpactAnalysis

let build = URL(filePath: ".build/impact")
let analysis = try ImpactAnalysis.analyze(build)

let toRun = allTests.filter { test in
    guard let reason = analysis.reasonToRun(test.id) else { return false }
    print("\(test.id): \(reason)")  // For example: "MyModule/Parser.swift changed".
    return true
}
```

Then launch the process that runs your tests with ``ImpactAnalysis/ImpactAnalysis/environment(for:)`` added to its environment, so its recordings are saved where the next analysis looks:

```swift
process.environment = ProcessInfo.processInfo.environment
    .merging(ImpactAnalysis.environment(for: build)) { $1 }
```

Analyze before every run. Each analysis takes stock of the build its run is about to use, which is what lets the next one make sense of that run's recordings.

### Decide what to do about failures

A `nil` reason means a test's last result still holds, whether it passed or failed. If your harness keeps results, it can report the last one. If it doesn't, run the tests that failed last time as well.

### When something goes wrong

SwiftImpact fails toward running tests:
- A test it has never seen, or whose recording it can't make sense of, needs to run.
- Clearing the build directory clears SwiftImpact's state too, and every test runs.
- If ``ImpactAnalysis/ImpactAnalysis/analyze(_:)`` throws, run every test, and show the error to say why.
- If the process under test isn't built for recording, recording does nothing, and its tests run next time.

### Keep running everything somewhere

SwiftImpact can't see some kinds of change, such as to resources and to code that isn't instrumented; <doc:Limitations> lists them. Keep a full run, such as in CI before merging, to catch what it can't.
