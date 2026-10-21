import ImpactCase

public let units = [
    Unit("describes-int") { describeInt() },
    Unit("describes-string") { describeString() },
    Unit("adds") { "\(sum())" },
]
