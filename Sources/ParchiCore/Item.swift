import CoreGraphics
import Foundation
import GRDB

public enum ItemKind: String, Codable, Sendable, CaseIterable {
    case note, todo, photo
}

public enum ItemState: String, Codable, Sendable {
    case active, archived, trashed
}

public enum PhotoLook: String, Codable, Sendable, CaseIterable {
    case stamp, tape, album, jharokha, bare

    public var name: String {
        switch self {
        case .stamp: return "Stamp"
        case .tape: return "Tape"
        case .album: return "Album"
        case .jharokha: return "Jharokha"
        case .bare: return "Bare"
        }
    }

    /// The arched and borderless looks have nowhere to put a line of text.
    public var showsCaption: Bool {
        switch self {
        case .stamp, .tape, .album: return true
        case .jharokha, .bare: return false
        }
    }
}

public struct TodoTask: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var text: String
    public var done: Bool

    public init(id: String = UUID().uuidString, text: String = "", done: Bool = false) {
        self.id = id
        self.text = text
        self.done = done
    }
}

/// A window frame in AppKit screen coordinates (origin at the bottom left).
public struct ItemFrame: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }

    public var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

public struct Item: Codable, Hashable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "item" }

    public var id: String
    public var kind: ItemKind
    public var state: ItemState
    public var title: String
    /// Plain text of a note. Used for search, export and as a fallback for `richText`.
    public var body: String
    /// RTF of a note's body.
    public var richText: Data?
    public var tasks: [TodoTask]
    public var photoFile: String?
    /// Width divided by height of the photo.
    public var photoAspect: Double?
    public var photoLook: PhotoLook
    public var themeID: String
    public var fontFamily: String?
    public var fontSize: Double
    public var opacity: Double
    public var onDesktop: Bool
    public var pinned: Bool
    public var allSpaces: Bool
    public var frame: ItemFrame?
    public var createdAt: Date
    public var updatedAt: Date
    public var trashedAt: Date?

    public init(kind: ItemKind, now: Date = Date()) {
        id = UUID().uuidString
        self.kind = kind
        state = .active
        title = ""
        body = ""
        richText = nil
        tasks = []
        photoFile = nil
        photoAspect = nil
        photoLook = .stamp
        themeID = "kagaz"
        fontFamily = nil
        fontSize = 16
        opacity = 1
        onDesktop = true
        pinned = false
        allSpaces = true
        frame = nil
        createdAt = now
        updatedAt = now
        trashedAt = nil
    }

    public var hasCaption: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Every piece of text a search should look at.
    public var searchableText: String {
        ([title, body] + tasks.map(\.text)).joined(separator: "\n")
    }

    public var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty { return trimmedTitle }
        let firstLine = body.split(whereSeparator: \.isNewline).first.map(String.init)
        if let firstLine, !firstLine.isEmpty { return firstLine }
        if let task = tasks.first(where: { !$0.text.isEmpty }) { return task.text }
        switch kind {
        case .note: return "Untitled note"
        case .todo: return "Untitled to-do list"
        case .photo: return "Photo"
        }
    }

    public var snippet: String {
        switch kind {
        case .note:
            return body.replacingOccurrences(of: "\n", with: " ")
        case .todo:
            let open = tasks.filter { !$0.done }.count
            return "\(open) of \(tasks.count) open"
        case .photo:
            return ""
        }
    }
}
