import ImpactCase

public let units = [
    Unit("first") { library.value },
    Unit("second") { library.value + "!" },
    Unit("adds") { "\(sum())" },
]
