import Foundation
import ImpactProbe

/// Work computed once per process and shared by the units that use it, as a harness caches a
/// context. Computing it is recorded as ``recording``, which units name in `dependsOn`.
public final class Shared<Value: Sendable>: @unchecked Sendable {
    public let name: String
    let fileID: String
    let make: @Sendable () -> Value
    let lock = NSLock()
    var cached: Value?

    public init(_ name: String, fileID: String = #fileID, _ make: @escaping @Sendable () -> Value) {
        self.name = name
        self.fileID = fileID
        self.make = make
    }

    /// The identifier computing it is recorded under.
    public var recording: String { "shared/\(name)" }

    /// The value, computed and recorded the first time it's asked for in a process. Adds itself
    /// as a dependency of the unit running on this thread, if that unit discovers its
    /// dependencies.
    public var value: Value {
        Discovery.current?.addDependency(recording)
        return lock.withLock {
            if let cached { return cached }
            let probe = ImpactProbe.start(test: recording, declaredIn: fileID)
            let value = make()
            probe.stop()
            cached = value
            return value
        }
    }
}
