import ImpactCase

public let units = [
    Unit("first", dependsOn: [library.recording]) { library.value },
    Unit("second", dependsOn: [library.recording]) { library.value + "!" },
    Unit("adds") { "\(sum())" },
]
