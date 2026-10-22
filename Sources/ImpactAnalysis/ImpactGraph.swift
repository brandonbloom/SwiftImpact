/// What a set of units depended on when they ran, to compare with later builds.
public struct ImpactGraph: Codable, Sendable {
    /// Every protocol conformance in the build the units last ran in.
    private(set) var conformances: [String]
    /// Each unit's footprint, by the unit's identifier.
    public private(set) var footprints: [String: Footprint]

    /// Records `footprints` of units that ran in the build `index` describes.
    public init(index: BuildIndex, footprints: [String: Footprint]) {
        conformances = index.allConformances.sorted()
        self.footprints = footprints
    }

    /// The units that may behave differently in the build `index` describes, each with why:
    /// objects in its footprint that changed, and conformances added or removed for its types.
    ///
    /// Units the graph lacks aren't included; run them too.
    public func affected(in index: BuildIndex) -> [String: [String]] {
        let changedConformances = Set(conformances).symmetricDifference(index.allConformances)
        var affected: [String: [String]] = [:]
        for (unit, footprint) in footprints {
            let reasons = footprint.changes(in: index) + footprint.uses(changedConformances)
            if !reasons.isEmpty { affected[unit] = reasons }
        }
        return affected
    }

    /// Records `footprints` of units that ran in the build `index` describes, replacing earlier
    /// ones for the same units, and moves the graph to that build.
    ///
    /// Units that didn't run keep their footprints, except those whose types gained or lost a
    /// conformance in the move: the graph forgets them, so they run next time.
    public mutating func record(_ footprints: [String: Footprint], in index: BuildIndex) {
        let changedConformances = Set(conformances).symmetricDifference(index.allConformances)
        self.footprints = self.footprints.filter {
            footprints[$0.key] == nil && $0.value.uses(changedConformances).isEmpty
        }
        self.footprints.merge(footprints) { $1 }
        conformances = index.allConformances.sorted()
    }

    /// Forgets `unit`'s footprint, such as after it failed, so it runs next time.
    public mutating func forget(_ unit: String) {
        footprints[unit] = nil
    }
}
