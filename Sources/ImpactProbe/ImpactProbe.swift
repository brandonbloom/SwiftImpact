import Darwin
import MachO

/// Records which instrumented functions run during a unit of work, such as one test or one
/// snapshot render.
///
/// Code built with `-profile-generate` keeps a counter per region of each function, in the
/// `__llvm_prf_cnts` section, and a record per function in `__llvm_prf_data`. The probe reads them
/// in place: ``reset()`` zeroes the counters, and ``executed()`` returns the name hash of every
/// function whose counters moved since. The harness maps those hashes to source files with
/// `TestImpact`.
///
/// Counters are process-wide, so a process can measure one unit at a time. Work that runs
/// concurrently with the unit is attributed to it too, which over-approximates its footprint.
public enum ImpactProbe {
  /// The size of a version 10 `__llvm_profile_data` record (LLVM 19 and later).
  static let recordSize = 64

  struct Image: @unchecked Sendable {
    let data: UnsafeRawBufferPointer
    let counters: UnsafeMutableRawBufferPointer
  }

  /// The instrumented images loaded at first use, or why the probe can't read them.
  static let images: Result<[Image], ProbeError> = {
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
      let image = Image(
        data: UnsafeRawBufferPointer(start: data, count: dataSize),
        counters: UnsafeMutableRawBufferPointer(start: counters, count: countersSize))
      if let problem = validate(image) { return .failure(problem) }
      images.append(image)
    }
    return images.isEmpty
      ? .failure(ProbeError(description: "no image is built with -profile-generate"))
      : .success(images)
  }()

  /// Why the probe can't run here.
  public struct ProbeError: Error, CustomStringConvertible, Sendable {
    public let description: String
  }

  /// Whether this process has instrumented code the probe can read; throws why not.
  public static func check() throws {
    _ = try images.get()
  }

  /// Zeroes every counter, starting a new unit.
  public static func reset() {
    guard case .success(let images) = images else { return }
    for image in images {
      image.counters.initializeMemory(as: UInt8.self, repeating: 0)
    }
  }

  /// The name hashes (`NameRef`) of the functions that ran since ``reset()``.
  public static func executed() -> [UInt64] {
    guard case .success(let images) = images else { return [] }
    var executed: [UInt64] = []
    for image in images {
      for record in stride(from: 0, to: image.data.count, by: recordSize) {
        let (nameRef, counters) = fields(of: record, in: image)
        if counters.contains(where: { $0 != 0 }) { executed.append(nameRef) }
      }
    }
    return executed
  }

  /// A record's name hash and its counters.
  static func fields(of offset: Int, in image: Image) -> (UInt64, UnsafeBufferPointer<UInt64>) {
    let record = image.data.baseAddress! + offset
    let nameRef = record.loadUnaligned(as: UInt64.self)
    // CounterPtr is relative to the record.
    let counterOffset = record.loadUnaligned(fromByteOffset: 16, as: Int64.self)
    let count = record.loadUnaligned(fromByteOffset: 48, as: UInt32.self)
    let start = (record + Int(counterOffset)).assumingMemoryBound(to: UInt64.self)
    return (nameRef, UnsafeBufferPointer(start: start, count: Int(count)))
  }

  /// Checks that `image`'s records have the layout the probe expects: each one's counters lie
  /// within the counters section, and together they account for all of it.
  static func validate(_ image: Image) -> ProbeError? {
    guard image.data.count % recordSize == 0 else {
      return ProbeError(description: "unexpected __llvm_prf_data record size")
    }
    let lower = UnsafeRawPointer(image.counters.baseAddress!)
    let upper = lower + image.counters.count
    var total = 0
    for record in stride(from: 0, to: image.data.count, by: recordSize) {
      let (_, counters) = fields(of: record, in: image)
      let start = UnsafeRawPointer(counters.baseAddress!)
      guard start >= lower, start + counters.count * 8 <= upper else {
        return ProbeError(description: "a profile record's counters lie outside the section")
      }
      total += counters.count * 8
    }
    guard total == image.counters.count else {
      return ProbeError(description: "profile records don't account for every counter")
    }
    return nil
  }
}
