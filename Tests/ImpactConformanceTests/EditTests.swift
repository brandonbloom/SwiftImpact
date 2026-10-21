import Testing

@testable import ImpactConformance

@Test func rendersEachSideOfAnEdit() {
    let source = """
        a
        #if IMPACT_AFTER
        after
        #else
        before
        #endif
        #if !IMPACT_AFTER  // only before
        gone
        #endif
        z
        """
    #expect(render(source, for: .before) == "a\nbefore\ngone\nz")
    #expect(render(source, for: .after) == "a\nafter\nz")
}

@Test func keepsOtherConditionalCompilation() {
    let source = """
        #if IMPACT_AFTER
        #if DEBUG
        debug
        #else
        release
        #endif
        #endif
        #if os(macOS)
        mac
        #endif
        """
    #expect(render(source, for: .before) == "#if os(macOS)\nmac\n#endif")
    #expect(
        render(source, for: .after)
            == "#if DEBUG\ndebug\n#else\nrelease\n#endif\n#if os(macOS)\nmac\n#endif")
}
