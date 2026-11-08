import FlitchCore
import Foundation
import ImageIO

/// A character = a folder with `pack.json`, `persona.<lang>.md` and `sprites/*.png` (horizontal strips).
/// Adding a character needs no code. See docs/architecture.md §8.
public struct CharacterPack: Codable, Sendable, Equatable {
    public struct Size: Codable, Sendable, Equatable {
        public var width: Int
        public var height: Int
    }

    public struct Animation: Codable, Sendable, Equatable {
        public enum Driver: String, Codable, Sendable { case time, audioLevel }
        public var file: String
        public var frames: Int
        /// Frames per second (ignored when driven by the audio level).
        public var fps: Double
        public var loop: Bool
        public var driver: Driver?
        /// Frame index → event name (e.g. "tap" to sync a sound).
        public var events: [String: String]?

        public var effectiveDriver: Driver { driver ?? .time }
    }

    public struct Behaviour: Codable, Sendable, Equatable {
        /// Idle activities with weights, e.g. [["juggle", 0.5], ["groom", 0.3]].
        public var idle: [[WeightedEntry]]?
        public var sleepAfter: Double?
    }

    /// One element of `[name, weight]` pairs.
    public enum WeightedEntry: Codable, Sendable, Equatable {
        case name(String)
        case weight(Double)
        public init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { self = .name(s) } else { self = .weight(try c.decode(Double.self)) }
        }
        public func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .name(let s): try c.encode(s)
            case .weight(let w): try c.encode(w)
            }
        }
    }

    public struct AnimalVoice: Codable, Sendable, Equatable {
        public var pitch: Double
        public var timbre: String
        public var speed: Double
        public var randomness: Double
    }

    public struct Voice: Codable, Sendable, Equatable {
        public var animal: AnimalVoice?
    }

    /// Discreet mode: how much of the character shows when it peeks in from a screen edge.
    public struct Peek: Codable, Sendable, Equatable {
        /// Rows (from the top of the frame) visible when fully peeked in.
        public var visibleRows: Int
        public var slideSeconds: Double
    }

    public var formatVersion: Int
    public var id: String
    public var name: String
    public var version: String
    public var author: String?
    public var license: String
    public var frame: Size
    /// Default on-screen pixel scale (points per sprite pixel).
    public var displayScale: Double?
    /// Named points inside the frame: "foot", "bubble", "peekEdge"…
    public var anchors: [String: [Int]]
    public var animations: [String: Animation]
    public var behaviour: Behaviour?
    public var voice: Voice?
    public var peek: Peek?

    /// Peek settings with defaults (upper ~70% of the frame).
    public var effectivePeek: Peek { peek ?? Peek(visibleRows: frame.height * 7 / 10, slideSeconds: 0.28) }

    /// Animations every character must provide for discreet mode.
    public static let requiredAnimations = ["idle", "listen", "think", "talk", "happy"]
    public static let supportedFormatVersion = 1

    /// Weighted idle activities as (name, weight).
    public var idleActivities: [(String, Double)] {
        (behaviour?.idle ?? []).compactMap { pair in
            guard pair.count == 2, case .name(let n) = pair[0], case .weight(let w) = pair[1] else { return nil }
            return (n, w)
        }
    }
}

public enum CharacterPackError: Error, Equatable, Sendable, CustomStringConvertible {
    case missingManifest(String)
    case invalidManifest(String)
    case unsupportedFormat(Int)
    case missingAnimation(String)
    case missingSprite(String)
    case unreadableSprite(String)
    case frameMismatch(animation: String, expected: String, actual: String)
    case anchorOutOfFrame(String)
    case invalidAnimation(String)
    case missingPersona(AppLanguage)

    public var description: String {
        switch self {
        case .missingManifest(let p): "pack.json not found in \(p)"
        case .invalidManifest(let m): "pack.json is invalid: \(m)"
        case .unsupportedFormat(let v):
            "pack format \(v) is not supported (expected \(CharacterPack.supportedFormatVersion))"
        case .missingAnimation(let a): "required animation '\(a)' is missing"
        case .missingSprite(let f): "sprite '\(f)' not found"
        case .unreadableSprite(let f): "sprite '\(f)' is not a readable PNG"
        case .frameMismatch(let a, let e, let x): "animation '\(a)': expected \(e) px, the strip is \(x) px"
        case .anchorOutOfFrame(let n): "anchor '\(n)' is outside the frame"
        case .invalidAnimation(let a): "animation '\(a)' needs at least one frame and a positive fps"
        case .missingPersona(let l): "persona.\(l.rawValue).md is missing"
        }
    }
}

/// A validated pack on disk.
public struct LoadedCharacter: Sendable {
    public let pack: CharacterPack
    public let directory: URL
    public let personas: [AppLanguage: String]

    public func spriteURL(_ animation: String) -> URL? {
        pack.animations[animation].map { directory.appendingPathComponent("sprites").appendingPathComponent($0.file) }
    }

    /// Persona in the language, falling back to English.
    public func persona(_ language: AppLanguage) -> String {
        personas[language] ?? personas[.english] ?? "You are \(pack.name)."
    }
}

public enum CharacterPackLoader {
    /// Loads and validates a pack folder. `requireAllLanguages` makes FR/ES personas mandatory (bundled packs).
    public static func load(from directory: URL, requireAllLanguages: Bool = false) throws -> LoadedCharacter {
        let manifest = directory.appendingPathComponent("pack.json")
        guard let data = try? Data(contentsOf: manifest) else {
            throw CharacterPackError.missingManifest(directory.path)
        }
        let pack: CharacterPack
        do {
            pack = try JSONDecoder().decode(CharacterPack.self, from: data)
        } catch {
            throw CharacterPackError.invalidManifest(String(describing: error))
        }
        try validate(pack, in: directory)

        var personas: [AppLanguage: String] = [:]
        for lang in AppLanguage.allCases {
            let url = directory.appendingPathComponent("persona.\(lang.rawValue).md")
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                personas[lang] = text.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if lang == .english || requireAllLanguages {
                throw CharacterPackError.missingPersona(lang)
            }
        }
        return LoadedCharacter(pack: pack, directory: directory, personas: personas)
    }

    static func validate(_ pack: CharacterPack, in directory: URL) throws {
        guard pack.formatVersion == CharacterPack.supportedFormatVersion else {
            throw CharacterPackError.unsupportedFormat(pack.formatVersion)
        }
        for name in CharacterPack.requiredAnimations where pack.animations[name] == nil {
            throw CharacterPackError.missingAnimation(name)
        }
        for (name, point) in pack.anchors {
            guard point.count == 2, (0..<pack.frame.width).contains(point[0]),
                (0..<pack.frame.height).contains(point[1])
            else { throw CharacterPackError.anchorOutOfFrame(name) }
        }
        for (name, anim) in pack.animations.sorted(by: { $0.key < $1.key }) {
            guard anim.frames > 0, anim.effectiveDriver == .audioLevel || anim.fps > 0 else {
                throw CharacterPackError.invalidAnimation(name)
            }
            let url = directory.appendingPathComponent("sprites").appendingPathComponent(anim.file)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw CharacterPackError.missingSprite(anim.file)
            }
            guard let size = imageSize(url) else { throw CharacterPackError.unreadableSprite(anim.file) }
            let expected = (pack.frame.width * anim.frames, pack.frame.height)
            guard size == expected else {
                throw CharacterPackError.frameMismatch(
                    animation: name, expected: "\(expected.0)×\(expected.1)", actual: "\(size.0)×\(size.1)")
            }
        }
    }

    static func imageSize(_ url: URL) -> (Int, Int)? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
            let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
            let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (w, h)
    }
}
