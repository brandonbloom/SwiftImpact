# How It Works

The mechanism behind selection: counters, objects, fingerprints, and the rules that cover what counters can't see.

## Overview

An analysis answers one question per test: could anything the test depended on have changed since it was recorded? SwiftImpact approximates "what it depended on" by the object files whose code it ran, and "changed" by those objects' fingerprints.

### Recording what runs

Code built with `-profile-generate` carries LLVM's instrumentation: a counter per region of each function, in the `__llvm_prf_cnts` section, and a 64-byte record per function in `__llvm_prf_data`, holding a hash of the function's name and where its counters are.

`ImpactProbe` finds those sections in each loaded image with `getsectiondata`, the first time a test starts. Starting a probe copies the counters; when it stops, every function whose counters moved since ran. The probe never writes the counters, so tests can be recorded concurrently, each seeing the others' work as its own. There is no profile file and no LLVM runtime API involved, so recording a test costs a copy and a pass over memory. Before trusting the records, the probe checks that their counters exactly tile the counters section.

The probe saves a recording for each test in the build directory: the test's identifier, the file declaring it, the name hashes of the functions it ran, and the `LC_UUID` of each instrumented image it ran in. A linked image's UUID changes whenever its code does, so the UUIDs name the build the test ran in.

### Mapping functions to source files

SwiftPM compiles each source file to an object of its own, before linking each module. Every object carries the `__llvm_prf_data` records of the functions it defines, so a name hash maps to its object by reading the objects alone, with no symbols or linker map. Each module's output file map, which SwiftPM writes beside its objects, gives the source file of each object.

Each analysis saves a snapshot of the build it sees: for each configuration, the UUIDs of its instrumented images, which object defines each function, and each object's fingerprint. A recording only makes sense against the build it was made in, so an analysis resolves each test's latest recording against the snapshot whose images it ran in. That gives the test's *footprint*: the objects whose code it ran, with their fingerprints then. The test's last result holds if every object in its footprint has the same fingerprint now.

A recording made in a build no analysis saw can't be resolved, and its test needs to run. Analyzing before every run guarantees the snapshot exists.

### Fingerprinting objects, not sources

An object's fingerprint hashes the platform and SDK it was built for (`LC_BUILD_VERSION`), and every section's bytes and relocations, with relocations naming their target symbols. It leaves out debug info (`__DWARF`) and the compiler's hash of its inputs (`__LLVM,__swift_modhash`), which change without the code changing.

Comparing objects rather than sources lets the compiler do the hard part. When an edit changes what code in another file means, such as a new overload changing what a call resolves to, Swift's incremental build recompiles that file, and its object changes. A comment or formatting change, conversely, usually reproduces the object byte for byte.

### Rules for what counters miss

Some dependencies run no instrumented code in the test that depends on them, so the footprint gets help:
- **Declaring files.** Code that macros generate has no counters. The harness names the file declaring each test, and it joins the test's footprint.
- **Globals.** A global or static variable is initialized once per process, so only the first test to read it runs its initializer. Its readers reference its addressor (`…vau`, `…vauZ`), which is visible in their objects' symbol tables. A footprint includes the objects defining every variable its objects read, transitively.
- **Conformances.** A conformance found at runtime, such as by `as? P`, changes behaviour without changing the code that asks. A snapshot keeps every conformance descriptor (`…Mc`) in the build, and a footprint the types its objects define or refer to. A conformance that comes or goes for one of those types means the test needs to run.

### Why by file

Selecting by function would select less: a test would skip changes to functions in its files that it never ran. But fingerprinting functions safely needs more rules, such as for witness tables and vtables, which per-file selection mostly gets for free because a type's tables share its object. SwiftImpact selects by file until that trade is measured more widely.
