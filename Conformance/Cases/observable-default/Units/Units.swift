import ImpactCase

public let units = [
    Unit("reads-count") { modelCount() },
    Unit("adds") { "\(sum())" },
]
