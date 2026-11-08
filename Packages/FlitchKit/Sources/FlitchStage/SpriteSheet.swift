import CoreGraphics
import FlitchCharacter
import Foundation
import ImageIO

/// The frames of every animation of a character, cut from the pack's PNG strips.
public final class SpriteSheet: @unchecked Sendable {
    public let character: LoadedCharacter
    private var frames: [String: [CGImage]] = [:]

    public init(character: LoadedCharacter) throws {
        self.character = character
        let size = character.pack.frame
        for (name, anim) in character.pack.animations {
            guard let url = character.spriteURL(name),
                let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                let strip = CGImageSourceCreateImageAtIndex(src, 0, nil)
            else { throw CharacterPackError.unreadableSprite(anim.file) }
            frames[name] = (0..<anim.frames).compactMap {
                strip.cropping(to: CGRect(x: $0 * size.width, y: 0, width: size.width, height: size.height))
            }
        }
    }

    public func frame(_ animation: String, _ index: Int) -> CGImage? {
        guard let list = frames[animation] ?? frames["idle"], !list.isEmpty else { return nil }
        return list[min(max(0, index), list.count - 1)]
    }
}
