/// Why a test needs to run, by kind of cause. Empty if its last result still holds.
struct Reasons: Sendable, Equatable {
    /// Why its recording couldn't be used, if it couldn't.
    var unusable: String?
    /// The `#fileID`s of files it depended on that changed.
    var changedFiles: [String] = []
    /// The descriptors of conformances that came or went for types it uses.
    var changedConformances: [String] = []
    /// The recordings it depends on that are impacted, or don't exist.
    var impactedDependencies: [String] = []
    var missingDependencies: [String] = []

    var isEmpty: Bool { all.isEmpty }

    /// One reason per cause.
    var all: [String] {
        (unusable.map { [$0] } ?? [])
            + changedFiles.map { "\($0) changed" }
            + changedConformances.map { "\(describe(conformance: $0)) came or went" }
            + impactedDependencies.map { "it depends on \($0), which is impacted" }
            + missingDependencies.map { "it depends on \($0), which has no recording" }
    }

    /// A short sentence: files by name, and other causes counted.
    var summary: String {
        if let unusable { return unusable }
        var parts: [String] = []
        if !changedFiles.isEmpty {
            parts.append("\(names(changedFiles)) changed")
        }
        switch changedConformances.count {
        case 0: break
        case 1: parts.append("\(describe(conformance: changedConformances[0])) came or went")
        case let count: parts.append("\(count) conformances of types it uses came or went")
        }
        switch impactedDependencies.count {
        case 0: break
        case 1: parts.append("it depends on \(impactedDependencies[0]), which is impacted")
        case let count: parts.append("it depends on \(count) impacted recordings")
        }
        switch missingDependencies.count {
        case 0: break
        case 1: parts.append("it depends on \(missingDependencies[0]), which has no recording")
        case let count: parts.append("it depends on \(count) recordings that don't exist")
        }
        return parts.isEmpty ? "its last result still holds" : parts.joined(separator: "; ")
    }
}

/// `items` by name, naming at most two.
func names(_ items: [String]) -> String {
    switch items.count {
    case 1: return items[0]
    case 2: return "\(items[0]) and \(items[1])"
    default: return "\(items[0]), \(items[1]), and \(items.count - 2) more"
    }
}

/// The protocol conformances that came or went between two builds, each by the type it's for.
///
/// Only conformances of types that exist in both builds count, or in neither, as a type from
/// another library does. A type that's new had no users before, and one that's gone, or
/// renamed, changed its users' code anyway.
struct ConformanceChanges: Sendable {
    /// The changed conformances' descriptors, by the mangling of the type each is for.
    let byType: [String: [String]]

    init(from before: BuildIndex, to after: BuildIndex) {
        let changed = before.allConformances.symmetricDifference(after.allConformances)
        guard !changed.isEmpty else {
            byType = [:]
            return
        }
        let definedBefore = before.allDefinedTypes
        let definedAfter = after.allDefinedTypes
        let types = before.allTypes.union(after.allTypes).union(definedBefore).union(definedAfter)
        var byType: [String: [String]] = [:]
        for conformance in changed {
            // A descriptor's mangling begins with its type's; the longest such type is exact,
            // so a nested type's conformance isn't its parent's.
            guard
                let type = types.filter({ conformance.hasPrefix($0) })
                    .max(by: { $0.count < $1.count }),
                definedBefore.contains(type) == definedAfter.contains(type)
            else { continue }
            byType[type, default: []].append(conformance)
        }
        self.byType = byType
    }

    /// The changed conformances of the types `footprint` uses.
    func used(by footprint: Footprint) -> [String] {
        footprint.types.flatMap { byType[$0] ?? [] }.sorted()
    }
}
