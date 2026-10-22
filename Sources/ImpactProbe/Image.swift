import Darwin
import MachO

/// A loaded image built with `-profile-generate`: its profile records and counters, read in
/// place.
///
/// Code built with `-profile-generate` keeps a counter per region of each function, in the
/// `__llvm_prf_cnts` section, and a record per function in `__llvm_prf_data`.
struct Image: @unchecked Sendable {
    /// The size of a version 10 `__llvm_profile_data` record (LLVM 19 and later).
    static let recordSize = 64

    let data: UnsafeRawBufferPointer
    let counters: UnsafeRawBufferPointer
    /// The image's `LC_UUID`, which identifies the build it came from.
    let uuid: String

    /// The instrumented images loaded in this process, or why the probe can't read them.
    static func loaded() -> Result<[Image], ProbeError> {
        var images: [Image] = []
        for index in 0..<_dyld_image_count() {
            guard let header = _dyld_get_image_header(index) else { continue }
            // Images in the shared cache are the system's, never instrumented.
            if header.pointee.flags & UInt32(MH_DYLIB_IN_CACHE) != 0 { continue }
            let header64 = UnsafeRawPointer(header).assumingMemoryBound(to: mach_header_64.self)
            var dataSize = 0
            var countersSize = 0
            guard
                let data = getsectiondata(header64, "__DATA", "__llvm_prf_data", &dataSize),
                let counters = getsectiondata(header64, "__DATA", "__llvm_prf_cnts", &countersSize)
            else { continue }
            guard let uuid = uuid(of: header64) else {
                return .failure(ProbeError(description: "an instrumented image has no LC_UUID"))
            }
            let image = Image(
                data: UnsafeRawBufferPointer(start: data, count: dataSize),
                counters: UnsafeRawBufferPointer(start: counters, count: countersSize),
                uuid: uuid)
            if let problem = image.validate() { return .failure(problem) }
            images.append(image)
        }
        return images.isEmpty
            ? .failure(ProbeError(description: "no image is built with -profile-generate"))
            : .success(images)
    }

    /// The `LC_UUID` of the image at `header`, formatted as `uuidgen` does.
    static func uuid(of header: UnsafePointer<mach_header_64>) -> String? {
        var command = UnsafeRawPointer(header) + MemoryLayout<mach_header_64>.size
        for _ in 0..<header.pointee.ncmds {
            let load = command.loadUnaligned(as: load_command.self)
            if load.cmd == UInt32(LC_UUID) {
                let bytes = (0..<16).map { command.load(fromByteOffset: 8 + $0, as: UInt8.self) }
                return format(uuid: bytes)
            }
            command += Int(load.cmdsize)
        }
        return nil
    }

    /// Calls `body` with each function's name hash (`NameRef`), the index of its first counter
    /// in the counters section, and its counters.
    func forEachFunction(_ body: (UInt64, Int, UnsafeBufferPointer<UInt64>) -> Void) {
        let base = counters.baseAddress!
        for offset in stride(from: 0, to: data.count, by: Self.recordSize) {
            let (nameRef, functionCounters) = fields(of: offset)
            body(
                nameRef, (UnsafeRawPointer(functionCounters.baseAddress!) - base) / 8,
                functionCounters)
        }
    }

    /// A record's name hash and its counters.
    func fields(of offset: Int) -> (UInt64, UnsafeBufferPointer<UInt64>) {
        let record = data.baseAddress! + offset
        let nameRef = record.loadUnaligned(as: UInt64.self)
        // CounterPtr is relative to the record.
        let counterOffset = record.loadUnaligned(fromByteOffset: 16, as: Int64.self)
        let count = record.loadUnaligned(fromByteOffset: 48, as: UInt32.self)
        let start = (record + Int(counterOffset)).assumingMemoryBound(to: UInt64.self)
        return (nameRef, UnsafeBufferPointer(start: start, count: Int(count)))
    }

    /// Checks that the records have the layout the probe expects: each one's counters lie within
    /// the counters section, and together they account for all of it.
    func validate() -> ProbeError? {
        guard data.count % Self.recordSize == 0 else {
            return ProbeError(description: "unexpected __llvm_prf_data record size")
        }
        let lower = counters.baseAddress!
        let upper = lower + counters.count
        var total = 0
        for offset in stride(from: 0, to: data.count, by: Self.recordSize) {
            let (_, functionCounters) = fields(of: offset)
            let start = UnsafeRawPointer(functionCounters.baseAddress!)
            guard start >= lower, start + functionCounters.count * 8 <= upper else {
                return ProbeError(
                    description: "a profile record's counters lie outside the section")
            }
            total += functionCounters.count * 8
        }
        guard total == counters.count else {
            return ProbeError(description: "profile records don't account for every counter")
        }
        return nil
    }
}

/// Why the probe can't record in this process.
struct ProbeError: Error, CustomStringConvertible {
    let description: String
}

/// Formats 16 bytes as an uppercase, hyphenated UUID.
func format(uuid bytes: [UInt8]) -> String {
    let hex = bytes.map { byte in
        let digits = Array("0123456789ABCDEF")
        return String([digits[Int(byte >> 4)], digits[Int(byte & 0xF)]])
    }
    return [0..<4, 4..<6, 6..<8, 8..<10, 10..<16].map { hex[$0].joined() }.joined(separator: "-")
}
