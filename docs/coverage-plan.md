# Coverage plan: a conformance suite and compatibility table

**Goal:** know, for every kind of change a Swift project can make and every toolchain we support, whether SwiftImpact selects the units it affects. Make that knowledge cheap to keep current.

## The property under test

For a build B0, an edit producing B1, and a unit U: **if U behaves differently in B1, U is selected.** That's safety. Precision is the share of selected units that behave differently.

Every case checks safety against an oracle rather than hand-written expectations: run every unit in both builds, compare outputs, and compare that with the selection. Each unit lands in one of four cells: selected and changed, selected and unchanged (over-selection), skipped and unchanged, or **skipped and changed (an escape)**.

Hand-written expectations exist only for known gaps (an expected escape, with a reason and a tracking link) and for precision baselines, so a regression in either is visible.

## No single authoritative list; four that cover different axes

| Axis | Question | Reference | Form |
|---|---|---|---|
| **Edits** | What can a change to Swift source be? | [`docs/LibraryEvolution.rst`](https://github.com/swiftlang/swift/blob/main/docs/LibraryEvolution.rst) | Per declaration kind (top-level functions and variables, structs, enums, protocols, classes, extensions, operators, typealiases), each permitted and forbidden change. Written for binary compatibility across modules, so it is the most systematic catalog of declaration-level edits. |
| | | [The Swift Programming Language: Reference](https://github.com/swiftlang/swift-book/tree/main/TSPL.docc/ReferenceManual) | `Declarations.md`, `Attributes.md`, `Expressions.md`, `Statements.md`, `Types.md`, `Patterns.md`, `GenericParametersAndArguments.md`. The grammar enumerates every construct; attributes enumerate the mechanisms (`@inlinable`, `@_dynamicReplacement`, `@objc`, `dynamic`, `@main`, property wrappers, result builders). |
| | | [`evolution.json`](https://download.swift.org/swift-evolution/v1/evolution.json) | Machine-readable swift-evolution: 559 proposals, 460 implemented, each with its Swift version. Not a catalog, but the authoritative feed of what's new. |
| | | [`test/InterfaceHash`](https://github.com/swiftlang/swift/tree/main/test/InterfaceHash) | The compiler's own 20 edit cases (added private method, changed var type, edited body, …) for its dependency hashing. |
| **Channels** | How can a change reach code that runs? | [`docs/ABI/Mangling.rst`](https://github.com/swiftlang/swift/blob/main/docs/ABI/Mangling.rst) | 126 `global ::=` productions: every kind of symbol the compiler emits (metadata `N`/`Ma`/`Mn`, conformances `Mc`/`Hc`, witness tables `WP`, vtables via `CMf`, method descriptors `Tq`, dispatch thunks `Tj`, keypath accessors `TK`/`Tk`, reabstraction and partial-application thunks, outlined value operations `WO*`, specializations, merged functions `Tm`, dynamic replacement `TI`/`TX`, back-deployment `Twb`), plus the accessor kinds (`vau`, getters, `_modify`, …). Each kind is a candidate channel. |
| | | [`docs/ABI/TypeMetadata.rst`](https://github.com/swiftlang/swift/blob/main/docs/ABI/TypeMetadata.rst), [`KeyPaths.md`](https://github.com/swiftlang/swift/blob/main/docs/ABI/KeyPaths.md), [`TypeLayout.rst`](https://github.com/swiftlang/swift/blob/main/docs/ABI/TypeLayout.rst) | What the runtime looks up by data rather than by call: the channels instrumentation can't see. |
| **Instrumentation** | Which code gets counters, so a footprint can see it ran? | [`lib/SIL/IR/SILProfiler.cpp`](https://github.com/swiftlang/swift/blob/main/lib/SIL/IR/SILProfiler.cpp) `shouldProfile` | The exclusions, in one function: generated code (every macro expansion), unavailable contexts, bodies replaced by body macros, and code without `hasUserWrittenCode` (synthesized conformances, implicit accessors, thunks). |
| | | [`test/Profiler`](https://github.com/swiftlang/swift/tree/main/test/Profiler) | 82 tests, one per construct the profiler handles specially: `coverage_lazy`, `coverage_macros`, `coverage_property_wrapper_backing`, `coverage_default_args`, `coverage_synthesized_witness`, `coverage_result_builder`, `coverage_deinit`, `coverage_clang_decls`, `coverage_toplevel`, `coverage_var_init`, … |
| **Formats** | What does the probe and index parse, and what changes across toolchains? | [`InstrProfData.inc`](https://github.com/llvm/llvm-project/blob/main/llvm/include/llvm/ProfileData/InstrProfData.inc), [`InstrProfileFormat.md`](https://github.com/llvm/llvm-project/blob/main/llvm/docs/InstrProfileFormat.md) | The `__llvm_profile_data` record layout and its version; the probe assumes version 10. |
| | | [`MachO.h`](https://github.com/llvm/llvm-project/blob/main/llvm/include/llvm/BinaryFormat/MachO.h) (or the SDK's `mach-o/loader.h`, `nlist.h`, `reloc.h`) | Load commands, sections, symbols, relocations: what `ObjectFile` reads. |

Two more for the harness design:
- [swift-driver's `IncrementalTestFramework`](https://github.com/swiftlang/swift-driver/tree/main/Tests/IncrementalTestFramework): modules, sources, and steps of edits, each with expected compilations. Close to the case format we want, with a behavioural oracle in place of expected compilations.
- Swift's incremental build model, [`docs/DependencyAnalysis.md`](https://github.com/swiftlang/swift/blob/main/docs/DependencyAnalysis.md): selection by object leans on it to recompile callers, for example when an overload added in one file changes what a call in another resolves to.

## Catalogs

Three checked-in catalogs give every item a stable ID, a link to its reference, and a status. The compatibility table is generated from them.

1. **Edits** (`E-…`): from LibraryEvolution's sections and TSPL's declarations, attributes, and expressions, plus edits outside Swift source:
   - C/ObjC sources and headers, prebuilt binaries and XCFrameworks;
   - resources (asset catalogs, bundled files, fonts, localizations);
   - the environment (toolchain, SDK, OS or simulator runtime, build flags, environment variables);
   - package manifests and dependency versions.
2. **Channels** (`C-…`): from Mangling.rst's symbol kinds, grouped by how they carry a change: direct calls, global initialization, runtime conformance lookup, witness-table and vtable dispatch, metadata and layout, keypaths, reflection (`Mirror`, `String(describing:)`), the ObjC runtime (selectors, `NSClassFromString`, KVO, `@objc dynamic`), dynamic replacement, cross-module inlining and specialization, default arguments, back deployment, and reads of files or resources.
3. **Features** (`F-…`): `evolution.json`'s implemented proposals, each triaged as *relevant* (gets a case), *covered by* another item, or *irrelevant* (with a one-line reason). This is what keeps the catalogs from going stale.

Each case names the edit and channel IDs it exercises. Coverage is the share of catalog items with a passing case or a documented gap.

## The suite

The suite lives in `Conformance/`, and `swift run swift-impact-conformance [<case>...]` runs it with the `swift` on `PATH`.

**A case** is a directory in `Conformance/Cases`: `case.json`, and a directory per module.
- **`case.json`** gives a one-line summary of the edit, optionally each module's dependencies, and any known escapes: units expected to escape, in which modes, and why.
- **Units:** the `Units` module declares `public let units: [Unit]`. Each unit is a name and a body returning a `String`, its observable behaviour, which is what the oracle compares. A unit's declaring file is always in its footprint, as a test's would be. Cases need only the toolchain: no UI frameworks.
- **The edit** is marked in the sources with `#if IMPACT_AFTER`, `#if !IMPACT_AFTER`, `#else`, and `#endif`. The files compile unrendered as the *before* side, so editors work on them. Rendering a side keeps its lines and drops the rest, so lines after an edit shift as they would after a real one. A file that renders blank doesn't exist on that side, which is how a case adds or removes one. The markers work in C and Objective-C sources too.

**The runner** generates each case's package under `.build/conformance/<case>`, with `ImpactProbe` and a harness executable. Then:
1. builds the *before* side with `-profile-generate`, indexes it, and runs every unit, recording each one's output and footprint;
2. writes the *after* side, changing only the files that differ, and builds again incrementally, as a developer's edit would be;
3. selects, and runs every unit again to compare outputs;
4. classifies every unit and checks the case's known escapes;
5. rebuilds the *after* side from clean and reports any object whose fingerprint differs from the incremental build's (`--no-clean-check` skips this).

Units run in two **modes**, each a column of the table:
- **shared:** every unit in one process, in order, as a test runner would. A unit can depend on state an earlier one set up, such as an initialized global.
- **isolated:** each unit in a process of its own.

Results go to `Conformance/Results/<environment>.json`, which is checked in, and the runner regenerates `docs/compatibility.md` from every results file. The diff of either shows a change in precision, so neither needs a hand-kept baseline. The runner exits nonzero if a unit escaped that isn't a known gap, a known gap closed, or the builds diverged.

## The environment matrix

- **Toolchains:** Swift and Xcode releases, and with them LLVM's profile record version and Swift's mangling. Installed side by side and chosen with `DEVELOPER_DIR` or `TOOLCHAINS`.
- **Build configuration:** debug and release, `-Onone` and `-O`, whole-module optimization, cross-module optimization, library evolution.
- **Platform:** macOS, then iOS and tvOS simulators.
- **Build system:** SwiftPM first; xcodebuild later, since its object layout differs.

A new toolchain is one new column. A failed probe validation or an unknown symbol kind is a result in that column, not a crash.

## Keeping it cheap

- **The oracle is the expectation.** Adding a case is writing an edit, not predicting its blast radius.
- **A symbol-kind census:** demangle every symbol in builds of real-world open-source packages and in the suite's builds, and report kinds seen in the wild that no case produces. That measures channel coverage without reading Mangling.rst by hand, and flags new kinds when a toolchain adds them.
- **A feature diff:** a script compares `evolution.json` with the feature catalog and lists implemented proposals not yet triaged.
- **Generated table:** nobody edits `compatibility.md`.
- **Plain SwiftPM:** `swift run swift-impact-conformance` runs the suite with the active toolchain; the matrix reruns it per installed toolchain with `TOOLCHAINS`.

## Milestones

1. **Harness.** Case format, runner, oracle, result JSON, and the table. Seed it with a case per rule already implemented, and a few neighbours: a literal in a body, in this module and another; a line shift, with and without `#line`; an overload in another file; a lazily initialized global; a conformance found at runtime; a new file; a witness from another file; a stored property's default value, plain and `@Observable`. Done when they all run and the table renders.
2. **Catalogs.** Edits, channels, and features with IDs and links; the census and the feature diff. Done when every item is either covered, a known gap, or triaged out.
3. **Known gaps first.** Cases for the known gaps, failing until fixed: uninstrumented C/ObjC and binaries, macro-generated code outside the declaring file, resources, the environment key, caches shared across units. Then the riskiest channels from the catalog: ObjC runtime, keypaths, reflection, dynamic replacement, `@inlinable` and cross-module specialization, default arguments.
4. **Matrix.** A second toolchain and release builds.
5. **Precision.** Precision baselines per case, so refinements such as exact conformance matching or per-function selection show their effect on the table.

## Open questions

- "Across multiple profiles or builds": I've read this as the toolchain and build-configuration matrix, with LLVM's profile format version as one of its dimensions.
- How many toolchains does CI need to keep installed?
