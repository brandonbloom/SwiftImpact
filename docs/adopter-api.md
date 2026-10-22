# Adopter API

SwiftImpact answers one question for a test harness:

> **Does this test's last result still hold for the code as it's built now?**

If it does, the harness can skip the test; if not, it runs it.

## API

```swift
// MARK: ImpactProbe — linked into the process that runs the tests

/// A test being recorded.
public struct ImpactProbe: Sendable {
    /// Starts recording `test`, declared in the file with `#fileID` `fileID`, or `nil` if that
    /// isn't known.
    ///
    /// `dependsOn` names other recordings the test depends on, such as of shared work; the test
    /// is impacted whenever one of them is, or has no recording.
    ///
    /// Records nothing unless the process was launched with `ImpactAnalysis.environment(for:)`
    /// and built with `ImpactAnalysis.buildArguments`.
    public static func start(
        test: String, declaredIn fileID: String?, dependsOn: [String] = []
    ) -> ImpactProbe

    /// Stops recording and saves what the test ran. Wait for any work the test started first.
    public func stop()
}

// MARK: ImpactAnalysis — used by the harness

public struct ImpactAnalysis: Sendable {
    /// Arguments to add to `swift build` or `swift test` for the code under test.
    public static let buildArguments: [String]

    /// Environment variables to launch the process under test with, so it records into the
    /// build in `buildDirectory`.
    public static func environment(for buildDirectory: URL) -> [String: String]

    /// Takes stock of the build in `buildDirectory` as it is now, and of the recordings made in
    /// it. Throws if the build can't be read; then run every test.
    public static func analyze(_ buildDirectory: URL) throws -> ImpactAnalysis

    /// Whether a change may have impacted `test`, so it needs to run: `true` unless its last
    /// result still holds, including for a test the analysis knows nothing about.
    public func isImpacted(_ test: String) -> Bool

    /// Why `test` is impacted or not, for a person to read. For display only: the wording may
    /// change, so don't parse it.
    public func explain(_ test: String) -> String
}
```

## Concepts

- **Tests** are identified by strings the harness chooses, stable from run to run. An identifier includes everything that changes what the test does: a snapshot rendered on two devices is two tests, such as `"CardView/iPhone"` and `"CardView/iPad"`.
- **A recording** is what one test ran, and the file declaring it. The probe saves it in the build directory.
- **An analysis** is a view of one build: what each recorded test depended on, compared with what's built now.
- **Results** are the harness's. A test that isn't impacted has a last result that still holds, whether it passed or failed; what to do about a failure is the harness's policy.

## Behaviour

- **The probe attaches itself** the first time a test starts in a process. If the process isn't instrumented, or wasn't launched with the analysis's environment, probes record nothing.
- **Probes can overlap.** Each records everything that ran in its process while it was started, so tests that run at once in one process each depend on what the others ran. That selects more tests, never fewer.
- **Platforms share a build directory.** Each configuration in it, such as `Debug` and `Debug-iphonesimulator`, is snapshotted separately. A simulator writes recordings to the host's file system; launched with `xcrun simctl`, it needs the environment's variables prefixed with `SIMCTL_CHILD_`.
- **Harnesses can share a build directory.** Each file is written atomically under a name of its own, and a snapshot or unreadable file is removed only once it's an hour old, so a concurrent harness's newer files survive until they're needed or stale.
- **State lives in the build directory**, under `impact/`, as a cache of that build. Clearing the build clears it, and every test runs.
- **The cycle is build, analyze, run.** Each analysis records the build its run is about to use, which the next analysis needs to make sense of that run's recordings.
- **Shared work is a recording of its own.** Work done once per process and reused by several tests, such as a cached context, runs inside at most one test's recording. Recording it under its own identifier, and naming that identifier in each dependent test's `dependsOn`, makes the dependents impacted whenever it is.
- **Everything uncertain means "run it":**
  - a test with no recording, or depending on a recording that doesn't exist;
  - a recording made in a build no analysis saw, or that doesn't fully resolve;
  - a build that can't be read, from `analyze` throwing.

## How it works

1. **A recording names its build.** The probe saves the test's identifier, its declaring file, the name hashes of the functions it ran, and the `LC_UUID` of each instrumented binary it ran in. A binary's UUID changes whenever its linked code does.
2. **An analysis saves a snapshot of its build:** which file each function comes from, and each file's fingerprint, keyed by the binaries' UUIDs.
3. **Recordings resolve against their own build.** A recording's functions are mapped to files using the snapshot with matching UUIDs. The test's last result holds if none of those files, nor the file declaring it, compiles differently now, and no type it uses gained or lost a protocol conformance.
4. **The toolchain and SDK are part of the build.** A new compiler changes the code it emits, and each object's fingerprint includes the SDK it was built against.

The documentation's How It Works and Limitations articles cover the selection rules and what they can't see.

## Open questions

- **Retired identifiers.** An analysis drops recordings that newer ones replaced, and snapshots nothing needs, but a test never run again keeps its recording until the build directory is cleared. Dropping those needs the harness to say which tests exist, or an age limit.
- **A Swift Testing trait** could record each test and find the build directory itself, making adoption for `swift test` close to one line. It would ship as a third module.

## Alternatives considered

- **An explicit `attach()` before recording.** It would need calling exactly once per process, with no benefit: attaching is idempotent, so it happens on first use.
- **An initializer to start a probe.** Starting copies the counters at that moment, an effect a static `start` makes visible at the call site.
- **Handing recordings to the harness to carry.** The process under test is usually not the harness, so the adopter would have to serialize and transport an opaque value. The build directory is already shared between the two.
- **A harness-declared environment.** Changes to the toolchain and SDK are visible in the build. Settings only the harness knows belong in test identifiers, where they also keep results for different settings apart.
- **Recording outcomes**, so failed tests are always selected. Whether to trust a past failure is harness policy, and a harness that keeps no results can rerun its last failures as most runners already do.
- **Structured reasons in the API**, as a list or an enum of causes. Code only needs whether to run a test, and people need a sentence; `explain` gives one, with no promise about its wording.
- **Separate build and graph types**, the graph persisted by the harness and the build indexed per run. Keeping state in the build directory lets one value answer for both.
- **A query by source file**, such as "which tests depend on this file?". Changes reach tests through files an edit didn't touch, when the compiler rebuilds them, so a file-based answer would miss what comparing builds catches.

The documentation's Adopting SwiftImpact article walks through adoption step by step.
