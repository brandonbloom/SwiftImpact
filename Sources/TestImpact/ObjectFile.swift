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

    init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count >= 32, data.load(UInt32.self, at: 0) == 0xFEED_FACF else {
            throw ObjectFileError(url: url, problem: "not a 64-bit Mach-O file")
        }
        var sections: [Section] = []
        var symbols: [Data] = []
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
                    let start = stringsOffset + Int(data.load(UInt32.self, at: symbolsOffset + index * 16))
                    let end = data[start...].firstIndex(of: 0) ?? data.endIndex
                    symbols.append(data[start..<end])
                }
            }
            offset += size
        }
        self.data = data
        self.sections = sections
        self.symbols = symbols
    }

    /// The name hash of each instrumented function the object defines.
    var profiledFunctions: [UInt64] {
        guard let section = sections.first(where: { $0.name == "__llvm_prf_data" }) else { return [] }
        return stride(from: 0, to: section.size, by: 64).map {
            data.load(UInt64.self, at: section.offset + $0)
        }
    }

    /// A hash of what the object does, ignoring debug info: each section's bytes and relocations,
    /// with relocations naming their symbols rather than indexing them.
    ///
    /// Recompiling an unchanged source file reproduces it. Moving code to other lines changes it,
    /// since the source location reaches code through `#fileID`, `#line`, and macro expansions.
    var fingerprint: String {
        var total = SHA256()
        for section in sections where section.segment != "__DWARF" {
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
                withUnsafeBytes(of: (address, info & 0xFF00_0000)) { hash.update(bufferPointer: $0) }
                hash.update(data: isExtern ? symbols[symbol] : Data("\(symbol)".utf8))
            }
            withUnsafeBytes(of: Array(hash.finalize())) { total.update(bufferPointer: $0) }
        }
        return total.finalize().prefix(12).map { String(format: "%02x", $0) }.joined()
    }
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
