# ``ImpactProbe``

Record what each test runs, from inside the process running it.

## Overview

ImpactProbe is the half of SwiftImpact that lives in the process running your tests. Start a probe as each test begins, and stop it when the test ends:

```swift
let probe = ImpactProbe.start(test: test.id, declaredIn: test.fileID)
test.run()
probe.stop()
```

The probe saves what the test ran in the build directory, where the harness's `ImpactAnalysis` finds it. It records only in a process built with `ImpactAnalysis.buildArguments` and launched with `ImpactAnalysis.environment(for:)`; anywhere else, it does nothing. The `ImpactAnalysis` documentation covers adoption, how it works, and its limitations.

The probe has no dependencies beyond the system, and records tests that run concurrently.

## Topics

### Recording

- ``ImpactProbe/ImpactProbe``
