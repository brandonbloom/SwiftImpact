# SwiftImpact

Run only the tests a change can affect.

> **Experimental.** Unpublished, and its interfaces will change.

SwiftImpact learns what each test exercises by watching it run. After a change, it tells your test runner which tests could now behave differently, and why; the runner skips the rest. It compares what the compiler built rather than source text, so it notices an edit in one file that changes the meaning of another, and it errs toward running a test when in doubt.

It's for suites whose tests are expensive, such as snapshot, UI, and integration tests, built with SwiftPM. A "test" is whatever unit of work your runner names.

## Documentation

`swift package docs` builds the DocC documentation, with a guide to adopting SwiftImpact, how it works, and its limitations, into one archive, and prints how to browse it. Xcode's Product › Build Documentation works too.

## Conformance

`swift run swift-impact-conformance` builds each case in `Conformance/Cases` before and after its edit, and checks that selection chooses every unit whose behaviour changed. The results by toolchain are in [docs/compatibility.md](docs/compatibility.md); the plan for coverage is in [docs/coverage-plan.md](docs/coverage-plan.md).
