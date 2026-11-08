import FlitchCore
import Foundation
import GRDB

/// A conversation saved in the history.
public struct ConversationRecord: Sendable, Hashable, Identifiable, Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "conversation"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
    public var id: Int64?
    public var startedAt: Date
    public var providerID: String?
    public var model: String?
    /// First question, for the list.
    public var title: String

    public init(id: Int64? = nil, startedAt: Date, providerID: String?, model: String?, title: String) {
        self.id = id
        self.startedAt = startedAt
        self.providerID = providerID
        self.model = model
        self.title = title
    }
}

public struct MessageRecord: Sendable, Hashable, Identifiable, Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "message"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
    public var id: Int64?
    public var conversationID: Int64
    public var role: String
    public var text: String
    public var createdAt: Date

    public var chatMessage: ChatMessage { ChatMessage(role: .init(rawValue: role) ?? .user, text: text) }

    enum CodingKeys: String, CodingKey {
        case id, role, text, createdAt
        case conversationID = "conversationId"
    }
}

/// Something Flitch remembers about the user.
public struct Memory: Sendable, Hashable, Identifiable, Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "memory"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
    public enum Status: String, Sendable, Codable { case pending, active }
    public enum Source: String, Sendable, Codable { case learned, user }

    public var id: Int64?
    public var text: String
    public var source: Source
    public var status: Status
    public var createdAt: Date
    /// Pinned memories are always in the prompt.
    public var pinned: Bool

    public init(
        id: Int64? = nil, text: String, source: Source = .learned, status: Status = .pending,
        createdAt: Date = Date(), pinned: Bool = false
    ) {
        self.id = id
        self.text = text
        self.source = source
        self.status = status
        self.createdAt = createdAt
        self.pinned = pinned
    }
}

/// "About me" (settings › Memory).
public struct UserProfile: Sendable, Hashable {
    public var name: String
    public var city: String
    public var about: String
    public init(name: String = "", city: String = "", about: String = "") {
        self.name = name
        self.city = city
        self.about = about
    }
    public var isEmpty: Bool { [name, city, about].allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
}

/// Flitch's local memory: history, profile and memories in one SQLite file
/// (`~/Library/Application Support/Flitch/flitch.sqlite`). Nothing leaves the Mac.
public final class MemoryStore: Sendable {
    private let db: any DatabaseWriter

    /// The app's database.
    public static func openDefault() throws -> MemoryStore {
        let dir = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appendingPathComponent("Flitch", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try MemoryStore(path: dir.appendingPathComponent("flitch.sqlite").path)
    }

    public init(path: String) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        db = try DatabasePool(path: path, configuration: config)
        try Self.migrator.migrate(db)
    }

    /// In memory, for tests and previews.
    public init() throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        db = try DatabaseQueue(configuration: config)
        try Self.migrator.migrate(db)
    }

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "conversation") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("startedAt", .datetime).notNull().indexed()
                t.column("providerID", .text)
                t.column("model", .text)
                t.column("title", .text).notNull()
            }
            try db.create(table: "message") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("conversation", onDelete: .cascade).notNull()
                t.column("role", .text).notNull()
                t.column("text", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "memory") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("text", .text).notNull()
                t.column("source", .text).notNull()
                t.column("status", .text).notNull().indexed()
                t.column("createdAt", .datetime).notNull()
                t.column("pinned", .boolean).notNull().defaults(to: false)
            }
            try db.create(table: "profile") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
            try db.create(virtualTable: "message_ft", using: FTS5()) { t in
                t.synchronize(withTable: "message")
                t.tokenizer = .unicode61(diacritics: .remove)
                t.column("text")
            }
            try db.create(virtualTable: "memory_ft", using: FTS5()) { t in
                t.synchronize(withTable: "memory")
                t.tokenizer = .unicode61(diacritics: .remove)
                t.column("text")
            }
        }
        return m
    }

    // MARK: - History

    /// Saves a closed conversation. Returns its id, or nil when there is nothing to save.
    @discardableResult
    public func saveConversation(
        _ messages: [ChatMessage], startedAt: Date = Date(), providerID: String? = nil, model: String? = nil
    ) throws -> Int64? {
        let messages = messages.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let first = messages.first(where: { $0.role == .user }) ?? messages.first else { return nil }
        return try db.write { db in
            var c = ConversationRecord(startedAt: startedAt, providerID: providerID, model: model, title: first.text)
            try c.insert(db)
            let id = c.id!
            for (i, m) in messages.enumerated() {
                var r = MessageRecord(
                    id: nil, conversationID: id, role: m.role.rawValue, text: m.text,
                    createdAt: startedAt.addingTimeInterval(Double(i) / 1000))
                try r.insert(db)
            }
            return id
        }
    }

    /// Most recent first. `search` matches any word of any message (accents ignored).
    public func conversations(search: String? = nil, limit: Int = 200) throws -> [ConversationRecord] {
        try db.read { db in
            if let search, let pattern = FTS5Pattern(matchingAllPrefixesIn: search) {
                return try ConversationRecord.fetchAll(
                    db,
                    sql: """
                        SELECT DISTINCT conversation.* FROM conversation
                        JOIN message ON message.conversationId = conversation.id
                        JOIN message_ft ON message_ft.rowid = message.id AND message_ft MATCH ?
                        ORDER BY conversation.startedAt DESC LIMIT ?
                        """, arguments: [pattern, limit])
            }
            return try ConversationRecord.order(Column("startedAt").desc).limit(limit).fetchAll(db)
        }
    }

    public func messages(in conversationID: Int64) throws -> [MessageRecord] {
        try db.read { db in
            try MessageRecord.filter(Column("conversationId") == conversationID).order(
                Column("createdAt"), Column("id")
            )
            .fetchAll(db)
        }
    }

    public func deleteConversation(_ id: Int64) throws {
        _ = try db.write { db in try ConversationRecord.deleteOne(db, key: id) }
    }

    public func deleteAllHistory() throws {
        _ = try db.write { db in try ConversationRecord.deleteAll(db) }
    }

    /// Deletes conversations started before `date`. Returns how many were deleted.
    @discardableResult
    public func purgeHistory(olderThan date: Date) throws -> Int {
        try db.write { db in try ConversationRecord.filter(Column("startedAt") < date).deleteAll(db) }
    }

    /// Applies a retention setting now.
    @discardableResult
    public func applyRetention(_ retention: HistoryRetention, now: Date = Date()) throws -> Int {
        switch retention {
        case .forever: return 0
        case .off:
            let n = try db.read { db in try ConversationRecord.fetchCount(db) }
            try deleteAllHistory()
            return n
        case .days90, .year:
            return try purgeHistory(olderThan: now.addingTimeInterval(-retention.seconds!))
        }
    }

    // MARK: - Memories

    @discardableResult
    public func addMemory(_ text: String, source: Memory.Source = .learned, status: Memory.Status = .pending)
        throws -> Memory
    {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return try db.write { db in
            // the same fact twice: keep one
            if let existing = try Memory.filter(Column("text").collating(.localizedCaseInsensitiveCompare) == text)
                .fetchOne(db)
            {
                if status == .active, existing.status == .pending {
                    var e = existing
                    e.status = .active
                    try e.update(db)
                    return e
                }
                return existing
            }
            var m = Memory(text: text, source: source, status: status)
            try m.insert(db)
            return m
        }
    }

    public func confirmMemory(_ id: Int64) throws {
        try db.write { db in
            guard var m = try Memory.fetchOne(db, key: id) else { return }
            m.status = .active
            try m.update(db)
        }
    }

    public func updateMemory(_ id: Int64, text: String? = nil, pinned: Bool? = nil) throws {
        try db.write { db in
            guard var m = try Memory.fetchOne(db, key: id) else { return }
            if let text { m.text = text.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let pinned { m.pinned = pinned }
            try m.update(db)
        }
    }

    public func deleteMemory(_ id: Int64) throws {
        _ = try db.write { db in try Memory.deleteOne(db, key: id) }
    }

    public func deleteAllMemories() throws {
        _ = try db.write { db in try Memory.deleteAll(db) }
    }

    /// Active memories, pinned first then newest first.
    public func memories(status: Memory.Status = .active) throws -> [Memory] {
        try db.read { db in
            try Memory.filter(Column("status") == status.rawValue)
                .order(Column("pinned").desc, Column("createdAt").desc, Column("id").desc).fetchAll(db)
        }
    }

    /// What goes in the prompt: pinned memories, then those matching the question, then the newest.
    public func relevantMemories(for question: String, limit: Int = 8) throws -> [String] {
        try db.read { db in
            let active = Column("status") == Memory.Status.active.rawValue
            var picked = try Memory.filter(active && Column("pinned") == true).order(Column("createdAt").desc)
                .limit(limit).fetchAll(db)
            func add(_ ms: [Memory]) {
                for m in ms where picked.count < limit && !picked.contains(where: { $0.id == m.id }) {
                    picked.append(m)
                }
            }
            if let pattern = FTS5Pattern(matchingAnyTokenIn: question) {
                add(
                    try Memory.fetchAll(
                        db,
                        sql: """
                            SELECT memory.* FROM memory JOIN memory_ft ON memory_ft.rowid = memory.id
                            WHERE memory_ft MATCH ? AND memory.status = 'active' ORDER BY rank LIMIT ?
                            """, arguments: [pattern, limit]))
            }
            add(try Memory.filter(active).order(Column("createdAt").desc, Column("id").desc).limit(limit).fetchAll(db))
            return picked.map(\.text)
        }
    }

    // MARK: - Profile

    public func profile() throws -> UserProfile {
        try db.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT key, value FROM profile")
            var values: [String: String] = [:]
            for r in rows { values[r["key"]] = r["value"] }
            return UserProfile(name: values["name"] ?? "", city: values["city"] ?? "", about: values["about"] ?? "")
        }
    }

    public func saveProfile(_ p: UserProfile) throws {
        try db.write { db in
            for (k, v) in [("name", p.name), ("city", p.city), ("about", p.about)] {
                try db.execute(sql: "INSERT OR REPLACE INTO profile(key, value) VALUES (?, ?)", arguments: [k, v])
            }
        }
    }

    /// Deletes history, memories and profile.
    public func deleteEverything() throws {
        try db.write { db in
            try ConversationRecord.deleteAll(db)
            try Memory.deleteAll(db)
            try db.execute(sql: "DELETE FROM profile")
        }
    }
}
