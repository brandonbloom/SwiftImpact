import Darwin

/// What a probe saves: the test, the file declaring it, the images it ran in, and the functions
/// it ran. `ImpactAnalysis` reads it.
struct RecordingFile {
    /// The format's version, which `ImpactAnalysis` checks.
    static let version = 1

    let test: String
    let declaredIn: String
    let images: [String]
    let functions: [UInt64]
    /// When it was saved, in nanoseconds since 1970, so the latest recording of a test wins.
    let time = clock_gettime_nsec_np(CLOCK_REALTIME)

    var json: String {
        let images = images.map(quoted).joined(separator: ",")
        let functions = functions.map(String.init).joined(separator: ",")
        return """
            {"version":\(Self.version),"test":\(quoted(test)),"declaredIn":\(quoted(declaredIn)),\
            "time":\(time),"images":[\(images)],"functions":[\(functions)]}
            """
    }
}

/// `string` as a JSON string literal.
func quoted(_ string: String) -> String {
    var result = "\""
    for scalar in string.unicodeScalars {
        switch scalar {
        case "\"": result += "\\\""
        case "\\": result += "\\\\"
        case "\n": result += "\\n"
        case "\r": result += "\\r"
        case "\t": result += "\\t"
        case _ where scalar.value < 0x20:
            let hex = String(scalar.value, radix: 16)
            result += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
        default: result.unicodeScalars.append(scalar)
        }
    }
    return result + "\""
}
