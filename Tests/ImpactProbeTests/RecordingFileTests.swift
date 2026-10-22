import Foundation
import Testing

@testable import ImpactProbe

@Test func encodesARecording() throws {
    let file = RecordingFile(
        test: "t", declaredIn: nil, dependsOn: ["shared"], images: ["U"], functions: [1, 2])
    let json = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(file)) as? [String: Any])
    #expect(json["version"] as? Int == 1)
    #expect(json["test"] as? String == "t")
    #expect(json["declaredIn"] == nil)
    #expect(json["dependsOn"] as? [String] == ["shared"])
    #expect(json["images"] as? [String] == ["U"])
    #expect(json["functions"] as? [UInt64] == [1, 2])
}

@Test func formatsUUIDs() {
    #expect(format(uuid: Array(0..<16)) == "00010203-0405-0607-0809-0A0B0C0D0E0F")
}
