import Foundation
import Testing

/// Every string catalog in the repo must be fully translated in French and Spanish.
struct LocalizationTests {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    static func catalogs() throws -> [URL] {
        let fm = FileManager.default
        var found: [URL] = []
        for dir in ["App", "Packages/FlitchKit/Sources"] {
            let base = repoRoot.appendingPathComponent(dir)
            guard let e = fm.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in e where url.pathExtension == "xcstrings" { found.append(url) }
        }
        return found
    }

    @Test func catalogsExist() throws {
        #expect(try Self.catalogs().count >= 3)
    }

    @Test(arguments: ["fr", "es"])
    func everyKeyIsTranslated(language: String) throws {
        for url in try Self.catalogs() {
            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
            let strings = json?["strings"] as? [String: Any] ?? [:]
            for (key, value) in strings {
                let locs = (value as? [String: Any])?["localizations"] as? [String: Any]
                let unit = (locs?[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                let ok = (unit?["state"] as? String) == "translated" && !((unit?["value"] as? String) ?? "").isEmpty
                #expect(ok, "\(url.lastPathComponent): '\(key)' missing \(language)")
            }
        }
    }
}
