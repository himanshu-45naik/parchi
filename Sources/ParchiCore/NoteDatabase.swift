import Foundation
import GRDB

public final class NoteDatabase: Sendable {
    private let queue: DatabaseQueue

    public init(path: String) throws {
        queue = try DatabaseQueue(path: path)
        try Self.migrator.migrate(queue)
    }

    /// A private in-memory database, for tests.
    public init() throws {
        queue = try DatabaseQueue()
        try Self.migrator.migrate(queue)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "item") { t in
                t.primaryKey("id", .text)
                t.column("kind", .text).notNull()
                t.column("state", .text).notNull().indexed()
                t.column("title", .text).notNull()
                t.column("body", .text).notNull()
                t.column("richText", .blob)
                t.column("tasks", .text).notNull()
                t.column("photoFile", .text)
                t.column("photoAspect", .double)
                t.column("photoFrameStyle", .text).notNull()
                t.column("photoRounded", .boolean).notNull()
                t.column("colorID", .text).notNull()
                t.column("patternID", .text).notNull()
                t.column("fontFamily", .text)
                t.column("fontSize", .double).notNull()
                t.column("opacity", .double).notNull()
                t.column("onDesktop", .boolean).notNull()
                t.column("pinned", .boolean).notNull()
                t.column("allSpaces", .boolean).notNull()
                t.column("frame", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("trashedAt", .datetime)
            }
        }
        migrator.registerMigration("v2-square-photo-frames") { db in
            try db.execute(sql: "UPDATE item SET photoRounded = 0 WHERE kind = 'photo'")
        }
        migrator.registerMigration("v3-themes-and-photo-looks") { db in
            try db.execute(sql: """
                UPDATE item SET colorID = CASE
                    WHEN patternID = 'ruled' THEN 'copy'
                    WHEN colorID IN ('yellow', 'peach') THEN 'haldi'
                    WHEN colorID IN ('coral', 'pink') THEN 'gulabi'
                    WHEN colorID IN ('lavender', 'sky') THEN 'inland'
                    WHEN colorID IN ('aqua', 'mint') THEN 'neem'
                    WHEN colorID IN ('slate', 'night') THEN 'raat'
                    ELSE 'kagaz'
                END;
                UPDATE item SET photoFrameStyle = CASE photoFrameStyle WHEN 'none' THEN 'bare' ELSE 'stamp' END;
                ALTER TABLE item RENAME COLUMN colorID TO themeID;
                ALTER TABLE item RENAME COLUMN photoFrameStyle TO photoLook;
                ALTER TABLE item DROP COLUMN patternID;
                ALTER TABLE item DROP COLUMN photoRounded;
                """)
        }
        return migrator
    }

    public func allItems() throws -> [Item] {
        try queue.read { db in
            try Item.order(Column("createdAt").desc).fetchAll(db)
        }
    }

    /// Inserts or updates all the given items in one transaction.
    public func save(_ items: [Item]) throws {
        guard !items.isEmpty else { return }
        try queue.write { db in
            for item in items {
                try item.save(db)
            }
        }
    }

    public func delete(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        try queue.write { db in
            _ = try Item.deleteAll(db, keys: ids)
        }
    }
}
