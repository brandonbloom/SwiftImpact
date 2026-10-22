/// What a unit of work depended on: each object whose code it ran, with that object's fingerprint
/// when it ran.
struct Footprint: Codable, Sendable, Equatable {
    /// The fingerprint of each object when the unit ran, by path relative to the build directory.
    var objects: [String: String] = [:]
    /// The manglings of the types its objects define or refer to. A conformance added or removed
    /// for one of them can change what it does through a runtime lookup, such as `as? P`,
    /// without changing any of its objects.
    var types: [String] = []
    /// Functions that ran, or sources named, that no indexed object accounts for, such as ones
    /// from a stale index.
    var unattributed = 0

    /// An empty footprint.
    init() {}

    /// The objects in this footprint that `index` lacks or fingerprints differently.
    func changes(in index: BuildIndex) -> [String] {
        objects.filter { index.fingerprints[$0.key] != $0.value }.map(\.key).sorted()
    }

    /// The conformances in `changed` that are for one of this footprint's types.
    func uses(_ changed: Set<String>) -> [String] {
        changed.filter { conformance in types.contains { conformance.hasPrefix($0) } }.sorted()
    }
}
