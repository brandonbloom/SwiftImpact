import Testing

@testable import ImpactProbe

@Test func quotesJSONStrings() {
    #expect(quoted("plain") == "\"plain\"")
    #expect(quoted("a \"b\" \\ c\n\u{1}") == "\"a \\\"b\\\" \\\\ c\\n\\u0001\"")
}

@Test func formatsUUIDs() {
    #expect(format(uuid: Array(0..<16)) == "00010203-0405-0607-0809-0A0B0C0D0E0F")
}
