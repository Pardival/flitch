import Foundation
import Testing

@testable import FlitchCore

/// Snapshot tests: the expected prompts live in `__Snapshots__/`.
/// Re-record with `RECORD_SNAPSHOTS=1 swift test --filter PromptBuilder`.
struct PromptBuilderTests {
    static let persona =
        "You are Flitch, a small river otter with headphones who lives in a corner of the user's screen."
    static let date = Date(timeIntervalSince1970: 1_794_150_000)  // Sunday 8 November 2026
    static let paris = TimeZone(identifier: "Europe/Paris")!

    @Test(arguments: AppLanguage.allCases)
    func basePrompt(language: AppLanguage) throws {
        let prompt = PromptBuilder().systemPrompt(
            .init(persona: Self.persona, language: language, date: Self.date, timeZone: Self.paris))
        try assertSnapshot(prompt, named: "base-\(language.rawValue)")
    }

    @Test func fullPromptWithProfileMemoriesAndSearch() throws {
        let prompt = PromptBuilder().systemPrompt(
            .init(
                persona: Self.persona, tone: .funny, language: .french, userName: "Kevin",
                profile: "Developer, lives in Lyon.", memories: ["Loves history", "Supports FC Barcelona"],
                canSearchWeb: true, date: Self.date, timeZone: Self.paris))
        try assertSnapshot(prompt, named: "full-fr")
    }

    @Test func emptyProfileSectionIsOmitted() {
        let prompt = PromptBuilder().systemPrompt(.init(persona: "P", userName: "  ", profile: ""))
        #expect(!prompt.contains("## About the user"))
    }

    @Test(arguments: TonePreset.allCases)
    func toneIsIncluded(tone: TonePreset) {
        let prompt = PromptBuilder().systemPrompt(.init(persona: "P", tone: tone))
        #expect(prompt.contains(tone.instruction))
    }
}

func assertSnapshot(_ value: String, named name: String, file: String = #filePath) throws {
    let dir = URL(fileURLWithPath: file).deletingLastPathComponent().appendingPathComponent("__Snapshots__")
    let url = dir.appendingPathComponent("\(name).txt")
    if ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
        || !FileManager.default.fileExists(atPath: url.path)
    {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try value.write(to: url, atomically: true, encoding: .utf8)
        return
    }
    let expected = try String(contentsOf: url, encoding: .utf8)
    #expect(value == expected, "Snapshot \(name) changed. Re-record with RECORD_SNAPSHOTS=1 if intended.")
}
