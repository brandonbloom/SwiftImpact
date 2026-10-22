import Foundation
import ImpactProbe

/// The probe of the unit running on this thread, for shared work to add itself to.
public enum Discovery {
    static let key = "ImpactCase.Discovery"

    /// The probe of the unit running on this thread, if it discovers its dependencies.
    static var current: ImpactProbe? {
        Thread.current.threadDictionary[key] as? ImpactProbe
    }

    /// Runs `body` with `probe` as the current thread's unit's probe.
    public static func run<T>(with probe: ImpactProbe, _ body: () -> T) -> T {
        Thread.current.threadDictionary[key] = probe
        defer { Thread.current.threadDictionary[key] = nil }
        return body()
    }
}
