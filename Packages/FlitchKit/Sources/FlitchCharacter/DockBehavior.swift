import Foundation

/// Small, seeded random generator (SplitMix64) so behaviour is reproducible in tests.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// The otter's idle life on the Dock: walk, stop and look, juggle, groom, dance, fall asleep on its back.
///
/// Pure logic: positions are in points along the Dock (`bounds`), time only moves through `tick`.
public struct DockBehavior: Sendable {
    public enum Activity: Equatable, Sendable {
        case walk(to: Double)
        case stand
        case look
        case play(String)  // juggle, groom, dance… (pack-defined)
        case sleep
        case wake
    }

    public struct Output: Equatable, Sendable {
        public var x: Double
        public var facingRight: Bool
        public var animation: String
    }

    public struct Tuning: Sendable {
        /// Points per second.
        public var walkSpeed: Double = 54
        /// Seconds without interaction before the otter may fall asleep.
        public var sleepAfter: Double = 180
        /// Idle activities and weights from the pack (juggle 0.5, groom 0.3…).
        public var plays: [(String, Double)] = []
        public init() {}
    }

    public private(set) var activity: Activity = .stand
    public private(set) var x: Double
    public private(set) var facingRight = true
    private var remaining: Double = 2
    private var idleFor: Double = 0
    private var rng: SeededRandom
    private let tuning: Tuning

    public init(tuning: Tuning, startX: Double, seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        self.tuning = tuning
        self.x = startX
        self.rng = SeededRandom(seed: seed)
    }

    /// Builds the tuning from a pack: `walkSpeed` is in sprite pixels, `scale` converts to points.
    public static func tuning(for pack: CharacterPack, scale: Double) -> Tuning {
        var t = Tuning()
        if let s = pack.behaviour?.walkSpeed { t.walkSpeed = s * scale }
        if let s = pack.behaviour?.sleepAfter { t.sleepAfter = s }
        t.plays = pack.idleActivities.filter { pack.animations[$0.0] != nil }
        return t
    }

    public var output: Output { Output(x: x, facingRight: facingRight, animation: animation) }

    private var animation: String {
        switch activity {
        case .walk: "walk"
        case .stand: "idle"
        case .look: "look"
        case .play(let name): name
        case .sleep: "sleepBack"
        case .wake: "wake"
        }
    }

    /// Advances by `dt` seconds within `bounds` (the Dock's walkable range, in points).
    @discardableResult
    public mutating func tick(_ dt: Double, bounds: ClosedRange<Double>) -> Output {
        idleFor += dt
        x = min(bounds.upperBound, max(bounds.lowerBound, x))
        switch activity {
        case .walk(let target):
            let target = min(bounds.upperBound, max(bounds.lowerBound, target))
            let step = tuning.walkSpeed * dt
            if abs(target - x) <= step {
                x = target
                next(bounds)
            } else {
                facingRight = target > x
                x += facingRight ? step : -step
            }
        default:
            remaining -= dt
            if remaining <= 0 { next(bounds) }
        }
        return output
    }

    /// Someone clicked, talked or the stage reappeared: wake up and pay attention.
    public mutating func interact() {
        idleFor = 0
        if activity == .sleep {
            start(.wake, for: 1.2)
        } else if case .walk = activity {
            start(.stand, for: 3)
        }
    }

    private mutating func next(_ bounds: ClosedRange<Double>) {
        if activity == .sleep {
            start(.wake, for: 1.2)
            return
        }
        if idleFor >= tuning.sleepAfter && activity != .wake {
            start(.sleep, for: Double.random(in: 60...150, using: &rng))
            return
        }
        let width = bounds.upperBound - bounds.lowerBound
        let playWeight = tuning.plays.isEmpty ? 0 : 0.3
        let roll = Double.random(in: 0..<1, using: &rng)
        if roll < 0.42 && width > 1 {
            // walk somewhere at least a fifth of the dock away
            var target = Double.random(in: bounds, using: &rng)
            if abs(target - x) < width / 5 {
                target =
                    x < bounds.lowerBound + width / 2 ? bounds.upperBound - width / 6 : bounds.lowerBound + width / 6
            }
            start(.walk(to: target), for: 0)
        } else if roll < 0.42 + playWeight {
            start(.play(pick()), for: Double.random(in: 3...6, using: &rng))
        } else if roll < 0.82 {
            start(.stand, for: Double.random(in: 1.5...4, using: &rng))
        } else {
            start(.look, for: 2)
        }
    }

    private mutating func pick() -> String {
        let total = tuning.plays.reduce(0) { $0 + $1.1 }
        var r = Double.random(in: 0..<max(total, .leastNonzeroMagnitude), using: &rng)
        for (name, w) in tuning.plays {
            if r < w { return name }
            r -= w
        }
        return tuning.plays.last?.0 ?? "idle"
    }

    private mutating func start(_ a: Activity, for seconds: Double) {
        activity = a
        remaining = seconds
    }
}
