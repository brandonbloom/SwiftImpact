# Limitations

What selection can miss, what it over-selects, and what a harness must handle itself.

## Overview

Selection is safe when every unit whose behaviour changes is selected. SwiftImpact's conformance suite checks that across kinds of edit, and its results are in the repository's `docs/compatibility.md`. The gaps below are known; some have cases recording them. <doc:HowItWorks> explains the mechanisms they refer to.

### Code without counters

A footprint holds the objects whose instrumented code a unit ran. Code with no counters is invisible to it:
- **Code macros generate**, such as `#Preview` bodies, `@Observable` accessors, and test registrations. Name the declaring file in `sources` (see <doc:Adopting>); generated code in other files is still unseen.
- **Code the compiler synthesizes**: implicit initializers, synthesized conformances, thunks, witness tables, and metadata.
- **C, Objective-C, and prebuilt binaries.**

A change to such code is caught only when the same object also holds instrumented code the unit ran. A known gap: a member added in another file can become a type's witness for a protocol requirement. The changed witness table lives in the conforming type's object, and if that object has no instrumented code the unit ran, the unit isn't selected.

### Runtime lookups

Global variables and conformances found at runtime are covered by rules of their own. Other ways the runtime finds code aren't: the Objective-C runtime (selectors, `NSClassFromString`, KVO), key paths, reflection beyond conformances, and dynamic replacement.

### What isn't tracked

- **Resources:** asset catalogs, bundled files, fonts, and localizations.
- **The environment:** the toolchain, SDK, OS or simulator runtime, build settings, and environment variables. An ``ImpactGraph`` doesn't record them; discard it, or run every unit, when they change.
- **Inputs from outside the build:** files, network responses, the clock, and state other processes leave behind.

### The process under test

- **One unit at a time.** Counters are per process. Work that runs concurrently with a unit, on other threads, is attributed to it, which over-selects but stays safe. A runner that runs units in parallel within one process must serialize them while recording.
- **The profile format is LLVM's**, version 10 of its per-function records (LLVM 19 and later). `ImpactProbe.check()` throws if the records don't have the layout it expects.

### The build

- **SwiftPM's layout.** ``BuildIndex/init(swiftPMBuild:)`` reads the per-file objects of SwiftPM's build system, under `out/Intermediates.noindex`. Other build systems, such as `xcodebuild`, are untested.
- **Incremental builds are trusted.** If the build fails to rebuild a file whose meaning an edit changed, selection misses it too.
- **Paths are part of the code.** File-private functions' profile names include their source path, so moving the checkout changes every object and selects every unit.
- **Unattributed functions.** A footprint counts the functions and sources no indexed object accounts for in ``Footprint/unattributed``, which suggests a stale index. Selection ignores it; a cautious harness runs such units every time.

### Over-selection

Selection is by object, so it selects more than changes:
- every unit that ran any of a changed file's code;
- every unit using a file that moved lines, when code embeds its location through `#line`, `#fileID`, or macro expansions;
- every unit using a file the compiler rebuilt, even where nothing that runs changed;
- every unit using a type whose name begins with that of a type whose conformances changed, since types are matched by prefix.
