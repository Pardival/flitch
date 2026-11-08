import Testing

@testable import FlitchCharacter

struct DockBehaviorTests {
    static func tuning() -> DockBehavior.Tuning {
        var t = DockBehavior.Tuning()
        t.walkSpeed = 50
        t.sleepAfter = 120
        t.plays = [("juggle", 0.5), ("groom", 0.3), ("dance", 0.2)]
        return t
    }

    static func run(seed: UInt64, seconds: Double, bounds: ClosedRange<Double> = 100...700) -> [DockBehavior.Output] {
        var b = DockBehavior(tuning: tuning(), startX: 400, seed: seed)
        return (0..<Int(seconds * 30)).map { _ in b.tick(1.0 / 30, bounds: bounds) }
    }

    @Test func sameSeedSameLife() {
        #expect(Self.run(seed: 42, seconds: 60) == Self.run(seed: 42, seconds: 60))
        #expect(Self.run(seed: 42, seconds: 60) != Self.run(seed: 7, seconds: 60))
    }

    @Test(arguments: [1, 2, 3, 4, 5] as [UInt64])
    func staysOnTheDock(seed: UInt64) {
        let out = Self.run(seed: seed, seconds: 120, bounds: 100...700)
        #expect(out.allSatisfy { (100...700).contains($0.x) })
    }

    @Test func walksAtTheConfiguredSpeedFacingItsDirection() {
        let out = Self.run(seed: 3, seconds: 120)
        for (a, b) in zip(out, out.dropFirst()) where a.animation == "walk" && b.animation == "walk" {
            let dx = b.x - a.x
            #expect(abs(dx) <= 50.0 / 30 + 0.0001)  // a full step, or the last bit to the target
            if dx != 0 { #expect(b.facingRight == (dx > 0)) }
        }
    }

    @Test func doesEverythingOverTime() {
        let animations = Set(Self.run(seed: 11, seconds: 400).map(\.animation))
        for name in ["walk", "idle", "juggle", "groom", "dance", "sleepBack"] {
            #expect(animations.contains(name), "never played \(name)")
        }
    }

    @Test func fallsAsleepAfterIdleTimeAndWakesOnInteraction() {
        var b = DockBehavior(tuning: Self.tuning(), startX: 400, seed: 5)
        var slept = false
        for _ in 0..<(200 * 30) {
            if b.tick(1.0 / 30, bounds: 100...700).animation == "sleepBack" {
                slept = true
                break
            }
        }
        #expect(slept)
        b.interact()
        #expect(b.activity == .wake)
        // no sleep right after waking up
        for _ in 0..<(30 * 30) { #expect(b.tick(1.0 / 30, bounds: 100...700).animation != "sleepBack") }
    }

    @Test func shrinkingDockClampsThePosition() {
        var b = DockBehavior(tuning: Self.tuning(), startX: 650, seed: 1)
        #expect(b.tick(0.01, bounds: 100...300).x == 300)
    }

    @Test func withoutPlaysItStillLives() {
        var t = Self.tuning()
        t.plays = []
        var b = DockBehavior(tuning: t, startX: 200, seed: 9)
        let names = Set((0..<3000).map { _ in b.tick(1.0 / 30, bounds: 0...400).animation })
        #expect(names.isSubset(of: ["walk", "idle", "look", "sleepBack", "wake"]))
    }
}
