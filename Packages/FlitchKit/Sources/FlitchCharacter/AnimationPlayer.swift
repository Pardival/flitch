import Foundation

/// Plays a pack's animations frame by frame. Pure logic: the stage calls `tick` from its display
/// timer and draws `frame` of `current`.
public struct AnimationPlayer: Sendable {
    public let pack: CharacterPack
    public private(set) var current: String
    public private(set) var frame = 0
    /// True when a non-looping animation reached its last frame.
    public private(set) var finished = false
    private var elapsed: Double = 0

    public init(pack: CharacterPack, animation: String = "idle") {
        self.pack = pack
        self.current =
            pack.animations[animation] != nil ? animation : (pack.animations.keys.sorted().first ?? animation)
    }

    public var spec: CharacterPack.Animation? { pack.animations[current] }

    /// Switches animation. Playing the current one again does nothing unless `restart`.
    public mutating func play(_ name: String, restart: Bool = false) {
        guard pack.animations[name] != nil else { return }
        guard name != current || restart else { return }
        current = name
        frame = 0
        elapsed = 0
        finished = false
    }

    /// Advances time; `level` (0…1) drives `audioLevel` animations. Returns events of frames entered.
    public mutating func tick(_ dt: Double, level: Float = 0) -> [String] {
        guard let spec else { return [] }
        if spec.effectiveDriver == .audioLevel {
            let f = min(spec.frames - 1, max(0, Int(level * Float(spec.frames))))
            return enter(f, spec)
        }
        guard !finished, spec.fps > 0, spec.frames > 1 else {
            if !spec.loop { finished = true }
            return []
        }
        elapsed += dt
        let step = 1 / spec.fps
        var events: [String] = []
        while elapsed >= step {
            elapsed -= step
            var next = frame + 1
            if next >= spec.frames {
                if spec.loop {
                    next = 0
                } else {
                    finished = true
                    elapsed = 0
                    break
                }
            }
            events += enter(next, spec)
        }
        return events
    }

    private mutating func enter(_ f: Int, _ spec: CharacterPack.Animation) -> [String] {
        guard f != frame else { return [] }
        frame = f
        return spec.events?[String(f)].map { [$0] } ?? []
    }
}
