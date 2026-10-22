import ImpactCase

public let units = [
    Unit("early") { early() },
    Unit("late") { late() },
    Unit("adds") { "\(sum())" },
]
