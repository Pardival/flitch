import FlitchCore
import Foundation
import Testing

@testable import FlitchCharacter

struct CharacterPackTests {
    static let charactersDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Characters")

    static func bundledPacks() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: charactersDir, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    /// Every pack shipped in the repo must be valid, with personas in all three languages.
    @Test func everyBundledPackIsValid() throws {
        let packs = try Self.bundledPacks()
        #expect(!packs.isEmpty)
        for dir in packs {
            let loaded = try CharacterPackLoader.load(from: dir, requireAllLanguages: true)
            #expect(loaded.pack.id == dir.lastPathComponent)
        }
    }

    @Test func otterPack() throws {
        let otter = try CharacterPackLoader.load(from: Self.charactersDir.appendingPathComponent("otter"))
        #expect(otter.pack.animations["talk"]?.effectiveDriver == .audioLevel)
        #expect(otter.pack.voice?.animal?.timbre == "squeak")
        #expect(otter.idleNames == ["juggle", "groom", "dance"])
        #expect(otter.persona(.french).contains("tu"))
        #expect(otter.spriteURL("idle")?.lastPathComponent == "idle.png")
    }

    // MARK: - Errors on a temporary pack

    func makePack(_ edit: (inout [String: Any]) -> Void, sprite: (name: String, width: Int)? = ("idle.png", 32))
        throws -> URL
    {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pack-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("sprites"), withIntermediateDirectories: true)
        let otter = Self.charactersDir.appendingPathComponent("otter")
        var json =
            try JSONSerialization.jsonObject(with: Data(contentsOf: otter.appendingPathComponent("pack.json")))
            as! [String: Any]
        edit(&json)
        try JSONSerialization.data(withJSONObject: json).write(to: dir.appendingPathComponent("pack.json"))
        try FileManager.default.copyItem(
            at: otter.appendingPathComponent("persona.en.md"), to: dir.appendingPathComponent("persona.en.md"))
        for f in try FileManager.default.contentsOfDirectory(atPath: otter.appendingPathComponent("sprites").path) {
            try FileManager.default.copyItem(
                at: otter.appendingPathComponent("sprites/\(f)"), to: dir.appendingPathComponent("sprites/\(f)"))
        }
        return dir
    }

    @Test func missingRequiredAnimation() throws {
        let dir = try makePack { j in
            var a = j["animations"] as! [String: Any]
            a["think"] = nil
            j["animations"] = a
        }
        #expect(throws: CharacterPackError.missingAnimation("think")) { try CharacterPackLoader.load(from: dir) }
    }

    @Test func frameCountMustMatchTheStrip() throws {
        let dir = try makePack { j in
            var a = j["animations"] as! [String: Any]
            var talk = a["talk"] as! [String: Any]
            talk["frames"] = 5
            a["talk"] = talk
            j["animations"] = a
        }
        #expect(throws: CharacterPackError.frameMismatch(animation: "talk", expected: "160×32", actual: "128×32")) {
            try CharacterPackLoader.load(from: dir)
        }
    }

    @Test func anchorsMustBeInsideTheFrame() throws {
        let dir = try makePack { j in j["anchors"] = ["foot": [16, 40]] }
        #expect(throws: CharacterPackError.anchorOutOfFrame("foot")) { try CharacterPackLoader.load(from: dir) }
    }

    @Test func missingSpriteFile() throws {
        let dir = try makePack { j in
            var a = j["animations"] as! [String: Any]
            var idle = a["idle"] as! [String: Any]
            idle["file"] = "nope.png"
            a["idle"] = idle
            j["animations"] = a
        }
        #expect(throws: CharacterPackError.missingSprite("nope.png")) { try CharacterPackLoader.load(from: dir) }
    }

    @Test func frenchPersonaRequiredForBundledPacks() throws {
        let dir = try makePack { _ in }
        #expect(throws: CharacterPackError.missingPersona(.french)) {
            try CharacterPackLoader.load(from: dir, requireAllLanguages: true)
        }
        #expect(try CharacterPackLoader.load(from: dir).persona(.french).hasPrefix("You are Flitch"))
    }

    @Test func unknownFormatVersion() throws {
        let dir = try makePack { j in j["formatVersion"] = 99 }
        #expect(throws: CharacterPackError.unsupportedFormat(99)) { try CharacterPackLoader.load(from: dir) }
    }
}

extension LoadedCharacter {
    var idleNames: [String] { pack.idleActivities.map(\.0) }
}
