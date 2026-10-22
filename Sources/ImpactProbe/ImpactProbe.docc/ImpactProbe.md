# ``ImpactProbe``

Record which functions each test runs, from inside the process running it.

## Overview

ImpactProbe is the half of SwiftImpact that lives in the process under test. Link it in, build that process with `-profile-generate`, create an ``ImpactProbe/ImpactProbe`` as each test starts, and call ``ImpactProbe/ImpactProbe/executed()`` when it ends. Hand what it returns to the harness, which uses the `ImpactAnalysis` module to decide what to run next time. That module's documentation covers adoption, how it works, and its limitations.

The probe has no dependencies beyond the system, writes no files itself, and can measure tests that run concurrently.

## Topics

### Recording

- ``ImpactProbe/ImpactProbe``
