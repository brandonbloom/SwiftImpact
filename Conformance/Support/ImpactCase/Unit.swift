/// A unit of work in a conformance case: a named body whose result is its observable behaviour.
public struct Unit: Sendable {
    public let name: String
    /// The `#fileID` of the file declaring the unit, which its footprint always includes.
    public let fileID: String
    /// The recordings of shared work the unit depends on.
    public let dependsOn: [String]
    let body: @Sendable () -> String

    public init(
        _ name: String, fileID: String = #fileID, dependsOn: [String] = [],
        _ body: @escaping @Sendable () -> String
    ) {
        self.name = name
        self.fileID = fileID
        self.dependsOn = dependsOn
        self.body = body
    }

    public func run() -> String { body() }
}
