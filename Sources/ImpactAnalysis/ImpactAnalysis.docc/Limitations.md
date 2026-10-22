# Limitations

What selection can miss, what it over-selects, and what a harness must handle itself.

## Overview

An analysis is safe when every test whose behaviour changes needs to run. SwiftImpact's conformance suite checks that across kinds of edit, and its results are in the repository's `docs/compatibility.md`. The gaps below are known; some have cases recording them. <doc:HowItWorks> explains the mechanisms they refer to.

### Code without counters

A footprint holds the objects whose instrumented code a test ran. Code with no counters is invisible to it:
- **Code macros generate**, such as `#Preview` bodies, `@Observable` accessors, and test registrations. Name the declaring file in `sources` (see <doc:Adopting>); generated code in other files is still unseen.
- **Code the compiler synthesizes**: implicit initializers, synthesized conformances, thunks, witness tables, and metadata.
- **C, Objective-C, and prebuilt binaries.**

A change to such code is caught only when the same object also holds instrumented code the test ran. A known gap: a member added in another file can become a type's witness for a protocol requirement. The changed witness table lives in the conforming type's object, and if that object has no instrumented code the test ran, the test isn't selected.

### Runtime lookups

Global variables and conformances found at runtime are covered by rules of their own. Other ways the runtime finds code aren't: the Objective-C runtime (selectors, `NSClassFromString`, KVO), key paths, reflection beyond conformances, and dynamic replacement.

### What isn't tracked

- **Resources:** asset catalogs, bundled files, fonts, and localizations.
- **The runtime environment:** the OS or simulator runtime, environment variables, and the harness's own settings. Changes to the toolchain and SDK show up in the build, but these don't. Include any that affect a test's result in its identifier, such as `"CardView/iPhone/iOS-18"`.
- **Inputs from outside the build:** files, network responses, the clock, and state other processes leave behind.

### The process under test

- **Parallel tests over-select.** Counters are per process, so everything that runs in a process while a test is recorded, including other tests, is attributed to it. That's safe, but the more tests overlap in one process, the more each selects. Running tests in parallel processes keeps them precise.
- **Work that outlives a test.** Code that runs after a test's probe stops, in work the test started, isn't attributed to the test. If it finishes before the next test begins, no recording includes it, and a later test that reads its results can be skipped wrongly. Wait for a test's work before stopping its probe.
- **Counters aren't atomic.** LLVM's instrumentation increments counters without synchronization. If a thread is preempted in the middle of an increment for the whole of a test, its late write can restore the count the test started with, hiding a function the test ran. The window is narrow but real for tests recorded in parallel.
- **The profile format is LLVM's**, version 10 of its per-function records (LLVM 19 and later). If the records don't have the layout it expects, the probe records nothing and says why on standard error, and the tests run next time.

### The build

- **SwiftPM's layout.** An analysis reads the per-file objects and linked products of SwiftPM's build system, under `out/Intermediates.noindex` and `out/Products`. Other build systems, such as `xcodebuild`, are untested.
- **Incremental builds are trusted.** If the build fails to rebuild a file whose meaning an edit changed, selection misses it too.
- **Paths are part of the code.** File-private functions' profile names include their source path, so moving the checkout changes every object and selects every test.

### Over-selection

Selection is by object, so it selects more than changes:
- every test that ran any of a changed file's code;
- every test using a file that moved lines, when code embeds its location through `#line`, `#fileID`, or macro expansions;
- every test using a file the compiler rebuilt, even where nothing that runs changed;
- every test using a type whose name begins with that of a type whose conformances changed, since types are matched by prefix.
