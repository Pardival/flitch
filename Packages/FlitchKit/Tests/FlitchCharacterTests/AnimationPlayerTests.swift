import Foundation
import Testing

@testable import FlitchCharacter

struct AnimationPlayerTests {
    static let pack: CharacterPack = {
        let json = """
            {"formatVersion":1,"id":"t","name":"T","version":"1","license":"MIT","frame":{"width":32,"height":32},
             "anchors":{},
             "animations":{
               "idle":{"file":"i.png","frames":4,"fps":4,"loop":true},
               "think":{"file":"t.png","frames":8,"fps":10,"loop":true,"events":{"5":"tap"}},
               "happy":{"file":"h.png","frames":3,"fps":10,"loop":false},
               "talk":{"file":"k.png","frames":4,"fps":0,"loop":true,"driver":"audioLevel"}}}
            """
        return try! JSONDecoder().decode(CharacterPack.self, from: Data(json.utf8))
    }()

    @Test func stepsAtTheAnimationFps() {
        var p = AnimationPlayer(pack: Self.pack)
        _ = p.tick(0.2)
        #expect(p.frame == 0)
        _ = p.tick(0.1)
        #expect(p.frame == 1)
        _ = p.tick(0.5)
        #expect(p.frame == 3)
        _ = p.tick(0.25)
        #expect(p.frame == 0)  // loops
    }

    @Test func onceStopsOnTheLastFrame() {
        var p = AnimationPlayer(pack: Self.pack)
        p.play("happy")
        _ = p.tick(1)
        #expect(p.frame == 2)
        #expect(p.finished)
        _ = p.tick(1)
        #expect(p.frame == 2)
    }

    @Test func eventsFireOncePerPass() {
        var p = AnimationPlayer(pack: Self.pack)
        p.play("think")
        var events: [String] = []
        for _ in 0..<16 { events += p.tick(0.1) }  // two full loops
        #expect(events == ["tap", "tap"])
    }

    @Test func audioLevelPicksTheFrame() {
        var p = AnimationPlayer(pack: Self.pack)
        p.play("talk")
        _ = p.tick(0.016, level: 0)
        #expect(p.frame == 0)
        _ = p.tick(0.016, level: 0.6)
        #expect(p.frame == 2)
        _ = p.tick(0.016, level: 1)
        #expect(p.frame == 3)
    }

    @Test func playingTheSameAnimationDoesNotRestart() {
        var p = AnimationPlayer(pack: Self.pack)
        _ = p.tick(0.5)
        p.play("idle")
        #expect(p.frame == 2)
        p.play("idle", restart: true)
        #expect(p.frame == 0)
        p.play("unknown")
        #expect(p.current == "idle")
    }
}
