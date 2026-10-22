import ImpactCase

public let units = [
    Unit("first", discoversDependencies: true) { library.value },
    Unit("second", discoversDependencies: true) { library.value + "!" },
    Unit("adds", discoversDependencies: true) { "\(sum())" },
]
