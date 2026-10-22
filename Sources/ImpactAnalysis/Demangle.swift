import Darwin

@_silgen_name("swift_demangle")
private func swiftDemangle(
    _ mangledName: UnsafePointer<CChar>?, _ mangledNameLength: UInt,
    _ outputBuffer: UnsafeMutablePointer<CChar>?, _ outputBufferSize: UnsafeMutablePointer<UInt>?,
    _ flags: UInt32
) -> UnsafeMutablePointer<CChar>?

/// The readable form of the Swift symbol `symbol`, as it appears in a symbol table, or `symbol`
/// itself if it isn't one.
func demangle(_ symbol: String) -> String {
    let mangled = symbol.hasPrefix("_$") ? String(symbol.dropFirst()) : symbol
    guard
        let demangled = mangled.withCString({
            swiftDemangle($0, UInt(strlen($0)), nil, nil, 0)
        })
    else { return symbol }
    defer { free(demangled) }
    return String(cString: demangled)
}

/// A protocol conformance descriptor's symbol as `Type : Protocol`.
func describe(conformance symbol: String) -> String {
    var description = demangle(symbol)
    if description.hasPrefix("protocol conformance descriptor for ") {
        description.removeFirst("protocol conformance descriptor for ".count)
    }
    if let module = description.range(of: " in ", options: .backwards) {
        description.removeSubrange(module.lowerBound...)
    }
    return "the conformance \(description)"
}
