# How It Works

The mechanism behind selection: counters, objects, fingerprints, and the rules that cover what counters can't see.

## Overview

Selection answers one question per unit: could anything the unit depended on have changed? SwiftImpact approximates "what it depended on" by the object files whose code it ran, and "changed" by those objects' fingerprints.

### Recording what runs

Code built with `-profile-generate` carries LLVM's instrumentation: a counter per region of each function, in the `__llvm_prf_cnts` section, and a 64-byte record per function in `__llvm_prf_data`, holding a hash of the function's name and where its counters are.

`ImpactProbe` finds those sections in each loaded image with `getsectiondata`. Resetting zeroes the counters; afterwards, every function whose counters moved ran. There is no profile file and no LLVM runtime API involved, so recording a unit costs a pass over memory. Before trusting the records, the probe checks that their counters exactly tile the counters section.

### Mapping functions to source files

SwiftPM compiles each source file to an object of its own, before linking each module. Every object carries the `__llvm_prf_data` records of the functions it defines, so ``BuildIndex`` maps a name hash to its object by reading the objects alone, with no symbols or linker map. Each module's output file map, which SwiftPM writes beside its objects, gives the source file of each object.

A ``Footprint`` is the set of objects whose functions a unit ran, each with its fingerprint at the time.

### Fingerprinting objects, not sources

An object's fingerprint hashes every section's bytes and relocations, with relocations naming their target symbols. It leaves out debug info (`__DWARF`) and the compiler's hash of its inputs (`__LLVM,__swift_modhash`), which change without the code changing.

Comparing objects rather than sources lets the compiler do the hard part. When an edit changes what code in another file means, such as a new overload changing what a call resolves to, Swift's incremental build recompiles that file, and its object changes. A comment or formatting change, conversely, usually reproduces the object byte for byte.

### Rules for what counters miss

Some dependencies run no instrumented code in the dependent unit, so the footprint gets help:
- **Declaring files.** Code that macros generate has no counters. The harness names the files a unit depends on regardless, at least the one declaring it, and they join its footprint.
- **Globals.** A global or static variable is initialized once per process, so only the first unit to read it runs its initializer. Its readers reference its addressor (`…vau`, `…vauZ`), which is visible in their objects' symbol tables. A footprint includes the objects defining every variable its objects read, transitively.
- **Conformances.** A conformance found at runtime, such as by `as? P`, changes behaviour without changing the code that asks. An ``ImpactGraph`` keeps every conformance descriptor (`…Mc`) in the build, and a footprint keeps the types its objects define or refer to. A conformance that comes or goes for one of those types selects the unit.

### Why by file

Selecting by function would select less: a unit would skip changes to functions in its files that it never ran. But fingerprinting functions safely needs more rules, such as for witness tables and vtables, which per-file selection mostly gets for free because a type's tables share its object. SwiftImpact selects by file until that trade is measured more widely.
