import CryptoKit
import Foundation

/// A 64-bit Mach-O relocatable object, as the compiler writes one per source file.
struct ObjectFile {
    struct Section {
        let segment: String
        let name: String
        let size: Int
        let offset: Int
        let relocationsOffset: Int
        let relocationCount: Int
        let flags: UInt32

        /// Zero-fill sections occupy no bytes in the file.
        var isZeroFill: Bool { [0x1, 0xC, 0x12].contains(flags & 0xFF) }
    }

    let data: Data
    let sections: [Section]
    /// Symbol names by index.
    let symbols: [Data]
    /// The names of the symbols the object defines, and of those it references but doesn't.
    let defined: [String]
    let undefined: [String]
    /// The `LC_BUILD_VERSION` command: the platform and SDK the object was built for.
    let buildVersion: Data

    init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count >= 32, data.load(UInt32.self, at: 0) == 0xFEED_FACF else {
            throw ObjectFileError(url: url, problem: "not a 64-bit Mach-O file")
        }
        var sections: [Section] = []
        var symbols: [Data] = []
        var defined: [String] = []
        var undefined: [String] = []
        var buildVersion = Data()
        var offset = 32
        for _ in 0..<data.load(UInt32.self, at: 16) {
            let command = data.load(UInt32.self, at: offset)
            let size = Int(data.load(UInt32.self, at: offset + 4))
            if command == 0x19 {  // LC_SEGMENT_64
                for index in 0..<Int(data.load(UInt32.self, at: offset + 64)) {
                    let at = offset + 72 + index * 80
                    sections.append(
                        Section(
                            segment: data.name(at: at + 16), name: data.name(at: at),
                            size: Int(data.load(UInt64.self, at: at + 40)),
                            offset: Int(data.load(UInt32.self, at: at + 48)),
                            relocationsOffset: Int(data.load(UInt32.self, at: at + 56)),
                            relocationCount: Int(data.load(UInt32.self, at: at + 60)),
                            flags: data.load(UInt32.self, at: at + 64)))
                }
            } else if command == 0x2 {  // LC_SYMTAB
                let symbolsOffset = Int(data.load(UInt32.self, at: offset + 8))
                let stringsOffset = Int(data.load(UInt32.self, at: offset + 16))
                for index in 0..<Int(data.load(UInt32.self, at: offset + 12)) {
                    let entry = symbolsOffset + index * 16
                    let start = stringsOffset + Int(data.load(UInt32.self, at: entry))
                    let end = data[start...].firstIndex(of: 0) ?? data.endIndex
                    symbols.append(data[start..<end])
                    // n_type: N_STAB debug entries aside, N_UNDF (0) or N_SECT (0xE).
                    let type = data.load(UInt8.self, at: entry + 4)
                    guard type & 0xE0 == 0 else { continue }
                    let name = String(decoding: data[start..<end], as: UTF8.self)
                    switch type & 0x0E {
                    case 0x0: undefined.append(name)
                    case 0xE: defined.append(name)
                    default: break
                    }
                }
            } else if command == 0x32 {  // LC_BUILD_VERSION
                buildVersion = data[offset..<offset + size]
            }
            offset += size
        }
        self.data = data
        self.sections = sections
        self.symbols = symbols
        self.defined = defined
        self.undefined = undefined
        self.buildVersion = buildVersion
    }

    /// Whether `symbol` is a Swift global or static variable's addressor: `unsafeMutableAddressor`
    /// (`vau`), static (`vauZ`).
    ///
    /// Code reads such a variable through its addressor, which the compiler generates without
    /// instrumentation, and the variable's initializer runs only once per process. So a unit that
    /// reads a variable another unit already initialized runs none of the defining file's code.
    static func isGlobalAddressor(_ symbol: String) -> Bool {
        symbol.hasPrefix("_$s") && (symbol.hasSuffix("vau") || symbol.hasSuffix("vauZ"))
    }

    /// The protocol conformances the object declares: their descriptors' symbols (`Mc`), which
    /// begin with the conforming type's mangling.
    var conformances: [String] {
        defined.filter { $0.hasPrefix("_$s") && $0.hasSuffix("Mc") }
    }

    /// The manglings of the types the object defines, from their nominal type descriptors (`Mn`).
    var definedTypes: Set<String> {
        Set(
            defined.filter { $0.hasPrefix("_$s") && $0.hasSuffix("Mn") }
                .map { String($0.dropLast(2)) })
    }

    /// The manglings of the types the object defines or refers to, from their metadata (`N`),
    /// metadata accessors (`Ma`), and nominal type descriptors (`Mn`).
    var types: Set<String> {
        var types = Set<String>()
        for symbol in defined + undefined where symbol.hasPrefix("_$s") {
            for suffix in ["Mn", "Ma", "N"] where symbol.hasSuffix(suffix) {
                types.insert(String(symbol.dropLast(suffix.count)))
                break
            }
        }
        return types
    }

    /// The name hash of each instrumented function the object defines.
    var profiledFunctions: [UInt64] {
        guard let section = sections.first(where: { $0.name == "__llvm_prf_data" }) else {
            return []
        }
        return stride(from: 0, to: section.size, by: 64).map {
            data.load(UInt64.self, at: section.offset + $0)
        }
    }

    /// A hash of what the object does: the platform and SDK it was built for, and each section's
    /// bytes and relocations, with relocations naming their symbols rather than indexing them. It
    /// ignores debug info, and the compiler's hash of its inputs (`__LLVM,__swift_modhash`),
    /// which changes when a file joins the module.
    ///
    /// Recompiling an unchanged source file reproduces it. Moving code to other lines changes it,
    /// since the source location reaches code through `#fileID`, `#line`, and macro expansions.
    var fingerprint: String {
        var total = SHA256()
        total.update(data: buildVersion)
        for section in sections
        where section.segment != "__DWARF" && section.name != "__swift_modhash" {
            var hash = SHA256()
            hash.update(data: Data("\(section.segment),\(section.name)".utf8))
            if !section.isZeroFill {
                hash.update(data: data[section.offset..<section.offset + section.size])
            }
            for index in 0..<section.relocationCount {
                let at = section.relocationsOffset + index * 8
                let address = data.load(UInt32.self, at: at)
                let info = data.load(UInt32.self, at: at + 4)
                let symbol = Int(info & 0xFF_FFFF)
                let isExtern = info >> 27 & 1 == 1
                withUnsafeBytes(of: (address, info & 0xFF00_0000)) {
                    hash.update(bufferPointer: $0)
                }
                hash.update(data: isExtern ? symbols[symbol] : Data("\(symbol)".utf8))
            }
            total.update(data: Data(hash.finalize()))
        }
        return total.finalize().prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}

/// The `LC_UUID` of the linked binary at `url`, if it's a 64-bit Mach-O executable, library, or
/// bundle built with `-profile-generate`, formatted as `uuidgen` does.
func instrumentedImageUUID(at url: URL) -> String? {
    guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count >= 32,
        data.load(UInt32.self, at: 0) == 0xFEED_FACF,
        [2, 6, 8].contains(data.load(UInt32.self, at: 12))  // MH_EXECUTE, MH_DYLIB, MH_BUNDLE
    else { return nil }
    var uuid: String?
    var instrumented = false
    var offset = 32
    for _ in 0..<data.load(UInt32.self, at: 16) {
        let command = data.load(UInt32.self, at: offset)
        if command == 0x1B {  // LC_UUID
            let hex = data[offset + 8..<offset + 24].map { String(format: "%02X", $0) }
            uuid = [0..<4, 4..<6, 6..<8, 8..<10, 10..<16].map { hex[$0].joined() }
                .joined(separator: "-")
        } else if command == 0x19 {  // LC_SEGMENT_64
            for index in 0..<Int(data.load(UInt32.self, at: offset + 64)) {
                instrumented =
                    instrumented || data.name(at: offset + 72 + index * 80) == "__llvm_prf_data"
            }
        }
        offset += Int(data.load(UInt32.self, at: offset + 4))
    }
    return instrumented ? uuid : nil
}

struct ObjectFileError: Error, CustomStringConvertible {
    let url: URL
    let problem: String
    var description: String { "\(url.path): \(problem)" }
}

extension Data {
    fileprivate func load<T: FixedWidthInteger>(_ type: T.Type, at offset: Int) -> T {
        withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) }
    }

    /// A fixed 16-byte, NUL-padded name.
    fileprivate func name(at offset: Int) -> String {
        let bytes = self[offset..<offset + 16]
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
}
