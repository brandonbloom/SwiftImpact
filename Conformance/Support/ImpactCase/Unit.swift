/// A unit of work in a conformance case: a named body whose result is its observable behaviour.
public struct Unit: Sendable {
    public let name: String
    /// The `#fileID` of the file declaring the unit, which its footprint always includes.
    public let fileID: String
    /// The recordings of shared work the unit is known to depend on before it runs.
    public let dependsOn: [String]
    /// Whether shared work the unit uses adds itself as a dependency as the unit runs, as a
    /// harness that learns what a test uses only while running it would.
    public let discoversDependencies: Bool
    let body: @Sendable () -> String

    public init(
        _ name: String, fileID: String = #fileID, dependsOn: [String] = [],
        discoversDependencies: Bool = false, _ body: @escaping @Sendable () -> String
    ) {
        self.name = name
        self.fileID = fileID
        self.dependsOn = dependsOn
        self.discoversDependencies = discoversDependencies
        self.body = body
    }

    public func run() -> String { body() }
}
