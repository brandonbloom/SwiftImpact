# SwiftImpact

Run only the tests a change can affect.

> **Experimental.** Its interfaces, and the state it keeps in the build directory, will change.

Most changes touch a small part of a codebase, yet a test suite reruns everything. That's costly for slow tests: snapshot renders, UI tests, integration tests. SwiftImpact records what each test runs, and after the next build tells your harness which tests' last results may no longer hold. The harness runs those and skips the rest.

It compares what the compiler built rather than source text, so it notices an edit in one file that changes what code in another means. When in doubt, it says to run the test.

## Using it

Add the package to the harness that builds and runs your tests:

```swift
.package(url: "https://github.com/brandonbloom/SwiftImpact", from: "0.1.0")
```

In the process that runs your tests, link `ImpactProbe` and record each test:

```swift
let probe = ImpactProbe.start(test: test.id, declaredIn: test.fileID)
test.run()
probe.stop()
```

In your harness, build the code under test with `ImpactAnalysis.buildArguments`, ask which tests to run, and launch them with `ImpactAnalysis.environment(for:)`:

```swift
let analysis = try ImpactAnalysis.analyze(buildDirectory)
let toRun = allTests.filter { analysis.isImpacted($0.id) }
```

The [documentation](https://brandonbloom.github.io/SwiftImpact/documentation/) walks through adoption, explains how it works, and lists what it can't see.

## Developing

- `swift test` runs the unit tests.
- `swift run swift-impact-conformance` builds each case in `Conformance/Cases` before and after an edit, and checks that every test whose behaviour changed is impacted. Results are in [docs/compatibility.md](docs/compatibility.md); [docs/coverage-plan.md](docs/coverage-plan.md) is the plan for coverage.
- `swift package docs` builds the documentation. [docs/adopter-api.md](docs/adopter-api.md) records the API's design.
