/// A side of a case's edit.
public enum Side: Sendable {
    case before, after
}

/// Renders a case's source file for one side of its edit.
///
/// A case marks its edit with `#if IMPACT_AFTER` or `#if !IMPACT_AFTER`, an optional `#else`, and
/// `#endif`, so each file compiles unrendered as its `before` side. Rendering keeps the lines of
/// `side` and drops the directives and the other side's lines, so the lines after an edit shift
/// as they would after a real one. Other conditional compilation blocks pass through.
func render(_ source: String, for side: Side) -> String {
    struct Block {
        /// Whether the block is an edit marker, and if so whether its current branch is kept.
        var isEdit: Bool
        var keeps: Bool
    }
    var blocks: [Block] = []
    var lines: [Substring] = []
    for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
        let words = line.split(whereSeparator: \.isWhitespace).prefix(2)
        let keeping = blocks.allSatisfy { !$0.isEdit || $0.keeps }
        switch (words.first, words.dropFirst().first) {
        case ("#if", "IMPACT_AFTER"):
            blocks.append(Block(isEdit: true, keeps: side == .after))
        case ("#if", "!IMPACT_AFTER"):
            blocks.append(Block(isEdit: true, keeps: side == .before))
        case ("#if", _):
            blocks.append(Block(isEdit: false, keeps: true))
            if keeping { lines.append(line) }
        case ("#else", _) where blocks.last?.isEdit == true:
            blocks[blocks.count - 1].keeps.toggle()
        case ("#endif", _) where blocks.last?.isEdit == true:
            blocks.removeLast()
        case ("#endif", _):
            blocks.removeLast()
            if keeping { lines.append(line) }
        default:
            if keeping { lines.append(line) }
        }
    }
    return lines.joined(separator: "\n")
}
