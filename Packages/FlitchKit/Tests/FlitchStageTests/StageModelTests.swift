import FlitchCore
import Foundation
import Testing

@testable import FlitchStage

@MainActor
struct StageModelTests {
    @Test func followsAFullTurn() {
        let m = StageModel()
        m.apply(.listening)
        #expect(m.visible && m.animation == "listen" && m.bubble == .listening(transcript: ""))
        m.apply(.partialTranscript("Parle-moi"))
        #expect(m.bubble == .listening(transcript: "Parle-moi"))
        m.apply(.transcribing)
        m.apply(.transcribed("Parle-moi de Napoléon"))
        m.apply(.thinking)
        #expect(m.bubble == .thinking && m.animation == "think")
        m.apply(.sentence("Né en 1769."))
        m.apply(.sentence("Mort en 1821."))
        #expect(m.bubble == .speaking(spoken: "Né en 1769.", current: "Mort en 1821."))
        #expect(m.animation == "talk")
        m.apply(.answerComplete("Né en 1769. Mort en 1821."))
        m.apply(.lingering(remaining: .seconds(15)))
        #expect(m.bubble == .lingering(text: "Né en 1769. Mort en 1821.", progress: 1))
        #expect(m.animation == "happy")
        m.apply(.lingering(remaining: .milliseconds(7500)))
        #expect(m.bubble == .lingering(text: "Né en 1769. Mort en 1821.", progress: 0.5))
        #expect(m.question == "Parle-moi de Napoléon")
        m.apply(.dismissed)
        #expect(!m.visible && m.bubble == .none)
    }

    @Test func errorStaysVisibleWhileLingering() {
        let m = StageModel()
        m.apply(.listening)
        m.apply(.error(.offline))
        m.apply(.lingering(remaining: .seconds(15)))
        #expect(m.bubble == .error(.offline))
    }

    @Test func citationsAreDeduplicated() {
        let m = StageModel()
        let c = Citation(title: "Wiki", url: URL(string: "https://example.org")!)
        m.apply(.listening)
        m.apply(.citation(c))
        m.apply(.citation(c))
        #expect(m.citations == [c])
    }

    @Test func errorActions() {
        #expect(StageModel.action(for: .noProvider) == .openSettings)
        #expect(StageModel.action(for: .invalidCredentials(provider: "X")) == .openSettings)
        #expect(StageModel.action(for: .microphoneDenied) == .openPrivacySettings)
        #expect(StageModel.action(for: .offline) == .retry)
        #expect(StageModel.action(for: .nothingHeard) == nil)
    }
}

@MainActor
struct MemoryChipTests {
    @Test func chipShowsUntilAnsweredOrDismissed() {
        let m = StageModel()
        m.apply(.listening)
        m.showMemory(.init(id: 7, fact: "Supports FC Barcelona", pending: true))
        #expect(m.memoryChip?.fact == "Supports FC Barcelona")
        m.clearMemory()
        #expect(m.memoryChip == nil)
        m.showMemory(.init(id: 8, fact: "x", pending: false))
        m.apply(.dismissed)
        #expect(m.memoryChip == nil)
    }
}

struct DockGeometryTests {
    @Test func estimatedWidthCountsPinnedRunningAndTrash() {
        var p = DockPrefs()
        p.tileSize = 48
        p.persistentApps = ["a", "b", "c"]
        let base = DockGeometry.estimatedWidth(prefs: p, runningApps: [], screenWidth: 2000)
        let more = DockGeometry.estimatedWidth(
            prefs: p, runningApps: ["a", "x", "com.apple.finder"], screenWidth: 2000)
        // Typed constants: untyped float literals in #expect are too slow to type-check on CI.
        let tile: CGFloat = 49.2
        let expectedBase: CGFloat = 5 * tile + 14 + 20
        let expectedMore: CGFloat = 6 * tile + 28 + 20
        #expect(base == expectedBase)
        #expect(more == expectedMore)
        #expect(DockGeometry.estimatedWidth(prefs: p, runningApps: [], screenWidth: 100) == 92)
    }

    @Test func autohideRevealsAfterDelayAndHidesWhenLeaving() {
        var r = AutohideReveal()
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        func at(_ x: CGFloat, _ y: CGFloat, _ t: Double) -> Bool {
            r.update(mouse: .init(x: x, y: y), screen: screen, dockHeight: 66, minX: 300, maxX: 700, delay: 0.5, now: t)
        }
        #expect(!at(500, 0, 0))
        #expect(!at(500, 0, 0.3))
        #expect(at(500, 1, 0.6))
        #expect(at(500, 50, 0.7))  // still over the Dock
        #expect(!at(500, 200, 0.8))  // left upwards
    }
}
