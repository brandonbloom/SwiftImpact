import ImpactCase

public let units = [
    Unit("warms") { warm() },
    Unit("reads") { readCache() },
    Unit("adds") { "\(sum())" },
]
