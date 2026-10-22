import ImpactCase

public let units = [
    Unit("computes") { computeOnAnotherThread() },
    Unit("adds") { "\(sum())" },
]
