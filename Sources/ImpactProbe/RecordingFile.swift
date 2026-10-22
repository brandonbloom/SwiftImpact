import Foundation

/// What a probe saves: the test, the file declaring it, the recordings it depends on, the images
/// it ran in, and the functions it ran. `ImpactAnalysis` reads it.
struct RecordingFile: Encodable {
    /// The format's version, which `ImpactAnalysis` checks.
    var version = 1
    let test: String
    let declaredIn: String?
    /// The other recordings the test depends on.
    let dependsOn: [String]
    let images: [String]
    let functions: [UInt64]
    /// When it was saved, in nanoseconds since 1970, so the latest recording of a test wins.
    var time = clock_gettime_nsec_np(CLOCK_REALTIME)
}
