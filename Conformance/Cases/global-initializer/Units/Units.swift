import ImpactCase

public let units = [
    Unit("first") { firstReader() },
    Unit("second") { secondReader() },
    Unit("adds") { "\(sum())" },
]
