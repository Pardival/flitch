import FlitchCore
import Foundation
import Testing

@testable import FlitchMemory

struct HistoryTests {
    let store = try! MemoryStore()

    @Test func savesAndReadsAConversation() throws {
        let id = try #require(
            try store.saveConversation(
                [
                    .user("Parle-moi de Napoléon"), .assistant("Il est né en 1769."), .user("Et sa mort ?"),
                    .assistant("En 1821."),
                ], providerID: "openrouter", model: "m"))
        let list = try store.conversations()
        #expect(list.count == 1)
        #expect(list[0].title == "Parle-moi de Napoléon")
        #expect(list[0].providerID == "openrouter")
        #expect(
            try store.messages(in: id).map(\.chatMessage).map(\.text) == [
                "Parle-moi de Napoléon", "Il est né en 1769.", "Et sa mort ?", "En 1821.",
            ])
    }

    @Test func emptyConversationIsNotSaved() throws {
        #expect(try store.saveConversation([.user("  ")]) == nil)
        #expect(try store.conversations().isEmpty)
    }

    @Test func searchIgnoresAccentsAndCase() throws {
        try store.saveConversation([.user("Parle-moi de Napoléon"), .assistant("Empereur.")])
        try store.saveConversation([.user("Quel temps fait-il ?"), .assistant("Il fait beau à Lyon.")])
        #expect(try store.conversations(search: "napoleon").map(\.title) == ["Parle-moi de Napoléon"])
        #expect(try store.conversations(search: "lyo").map(\.title) == ["Quel temps fait-il ?"])
        _ = try store.conversations(search: "\"*(")  // odd input never throws
        #expect(try store.conversations(search: "pingouin").isEmpty)
    }

    @Test func newestFirst() throws {
        let now = Date()
        try store.saveConversation([.user("old")], startedAt: now.addingTimeInterval(-100))
        try store.saveConversation([.user("new")], startedAt: now)
        #expect(try store.conversations().map(\.title) == ["new", "old"])
    }

    @Test(arguments: [
        (HistoryRetention.forever, ["today", "200 days", "2 years"]),
        (.year, ["today", "200 days"]),
        (.days90, ["today"]),
        (.off, [String]()),
    ])
    func retention(_ retention: HistoryRetention, kept: [String]) throws {
        let store = try MemoryStore()
        let now = Date()
        try store.saveConversation([.user("today")], startedAt: now)
        try store.saveConversation([.user("200 days")], startedAt: now.addingTimeInterval(-200 * 86_400))
        try store.saveConversation([.user("2 years")], startedAt: now.addingTimeInterval(-730 * 86_400))
        try store.applyRetention(retention, now: now)
        #expect(try store.conversations().map(\.title) == kept)
    }

    @Test func deletingAConversationDeletesItsMessages() throws {
        let id = try #require(try store.saveConversation([.user("a"), .assistant("b")]))
        try store.deleteConversation(id)
        #expect(try store.messages(in: id).isEmpty)
        #expect(try store.conversations(search: "a").isEmpty)
    }

    @Test func persistsOnDisk() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("flitch-\(UUID()).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        do {
            let s = try MemoryStore(path: path)
            try s.saveConversation([.user("hello")])
            try s.saveProfile(.init(name: "Kevin"))
        }
        let s = try MemoryStore(path: path)
        #expect(try s.conversations().map(\.title) == ["hello"])
        #expect(try s.profile().name == "Kevin")
    }
}

struct MemoryTests {
    let store = try! MemoryStore()

    @Test func pendingUntilConfirmed() throws {
        let m = try store.addMemory("Supports FC Barcelona")
        #expect(m.status == .pending)
        #expect(try store.memories().isEmpty)
        #expect(try store.relevantMemories(for: "football").isEmpty)
        try store.confirmMemory(m.id!)
        #expect(try store.memories().map(\.text) == ["Supports FC Barcelona"])
    }

    @Test func sameFactIsKeptOnce() throws {
        try store.addMemory("Loves history", status: .active)
        try store.addMemory("loves history", status: .active)
        #expect(try store.memories().count == 1)
    }

    @Test func relevantPutsPinnedThenMatchesThenNewest() throws {
        let pinned = try store.addMemory("Name of the cat is Moka", status: .active)
        try store.updateMemory(pinned.id!, pinned: true)
        try store.addMemory("Supports FC Barcelona", status: .active)
        try store.addMemory("Allergic to peanuts", status: .active)
        try store.addMemory("Learns Spanish", status: .active)
        let r = try store.relevantMemories(for: "Who won the Barcelona match?", limit: 3)
        #expect(r.first == "Name of the cat is Moka")
        #expect(r[1] == "Supports FC Barcelona")
        #expect(r.count == 3)
    }

    @Test func editAndForget() throws {
        let m = try store.addMemory("Lives in Lyon", source: .user, status: .active)
        try store.updateMemory(m.id!, text: "Lives in Paris")
        #expect(try store.memories().map(\.text) == ["Lives in Paris"])
        #expect(try store.relevantMemories(for: "paris") == ["Lives in Paris"])
        try store.deleteMemory(m.id!)
        #expect(try store.memories().isEmpty)
    }

    @Test func profileRoundTrip() throws {
        #expect(try store.profile().isEmpty)
        try store.saveProfile(.init(name: "Kevin", city: "Lyon", about: "Developer"))
        #expect(try store.profile() == UserProfile(name: "Kevin", city: "Lyon", about: "Developer"))
    }

    @Test func deleteEverything() throws {
        try store.saveConversation([.user("x")])
        try store.addMemory("y", status: .active)
        try store.saveProfile(.init(name: "z"))
        try store.deleteEverything()
        #expect(try store.conversations().isEmpty && store.memories().isEmpty && store.profile().isEmpty)
    }
}
