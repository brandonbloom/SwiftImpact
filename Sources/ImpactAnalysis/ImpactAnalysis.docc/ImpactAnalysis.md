# ``ImpactAnalysis``

Run only the tests a change can affect.

## Overview

Most changes touch a small part of a codebase, yet a test suite reruns everything. That's tolerable for fast unit tests and costly for slow ones: snapshot renders, UI tests, and integration tests that take seconds each.

SwiftImpact learns what each test actually exercises, by watching it run. After you change the code, it tells your test runner which tests could now behave differently, and why. The runner runs those and skips the rest.

- **Driven by what runs, not by guesses.** It doesn't infer dependencies from imports or file names; it records the code each test executed, down to the source file.
- **Driven by what the compiler built.** It compares compiled output, so it notices when an edit in one file changes the meaning of code in another, and usually ignores edits, such as to comments, that change nothing the compiler emits.
- **Safe by default.** When in doubt, it runs the test. The kinds of change it can't see are listed in <doc:Limitations>, and a conformance suite checks it against a growing catalog of edits.
- **Harness-neutral.** A "test" is any unit of work your runner names: a test case, a snapshot, a benchmark.
- **Plain SwiftPM.** No build plugins, daemons, or project changes beyond a compiler flag for the code under test.

> Important: SwiftImpact is experimental. Its interfaces and the format it stores will change. Keep running every test somewhere, such as in CI.

## Topics

### Essentials

- <doc:Adopting>

### Understanding SwiftImpact

- <doc:HowItWorks>
- <doc:Limitations>

### Analyzing a build

- ``ImpactAnalysis/ImpactAnalysis``
