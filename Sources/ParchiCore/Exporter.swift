import Foundation

public enum ExportFormat: String, Codable, Sendable, CaseIterable {
    case text, markdown

    public var fileExtension: String {
        switch self {
        case .text: return "txt"
        case .markdown: return "md"
        }
    }

    public var label: String {
        switch self {
        case .text: return "Plain text (.txt)"
        case .markdown: return "Markdown (.md)"
        }
    }
}

public enum Exporter {
    public static func render(_ item: Item, format: ExportFormat) -> String {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        var output = ""
        if !title.isEmpty {
            output += format == .markdown ? "# \(title)\n\n" : "\(title)\n\n"
        }
        if item.kind == .todo {
            output += item.tasks.map { task in
                let mark = task.done ? "x" : " "
                return format == .markdown ? "- [\(mark)] \(task.text)" : "[\(mark)] \(task.text)"
            }.joined(separator: "\n")
        } else {
            output += item.body
        }
        if !output.hasSuffix("\n") { output += "\n" }
        return output
    }

    public static func fileName(for item: Item) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?*\"<>|").union(.controlCharacters).union(.newlines)
        let cleaned = item.displayTitle
            .components(separatedBy: forbidden)
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        let limited = String(cleaned.prefix(80))
        return limited.isEmpty ? "Untitled" : limited
    }

    /// Writes every note and to-do list in `items` into a new folder inside `parent`.
    /// Photos are skipped. A partly written folder is removed if anything fails.
    public static func export(
        _ items: [Item],
        format: ExportFormat,
        into parent: URL,
        now: Date = Date()
    ) throws -> (folder: URL, count: Int) {
        let manager = FileManager.default
        let exportable = items.filter { $0.kind != .photo }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        let folder = uniqueURL(in: parent, base: "Parchi Export \(formatter.string(from: now))", ext: nil)

        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            for item in exportable {
                let url = uniqueURL(in: folder, base: fileName(for: item), ext: format.fileExtension)
                try render(item, format: format).write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            try? manager.removeItem(at: folder)
            throw error
        }
        return (folder, exportable.count)
    }

    private static func uniqueURL(in folder: URL, base: String, ext: String?) -> URL {
        let manager = FileManager.default
        func candidate(_ name: String) -> URL {
            let url = folder.appendingPathComponent(name)
            return ext.map { url.appendingPathExtension($0) } ?? url
        }
        var url = candidate(base)
        var suffix = 2
        while manager.fileExists(atPath: url.path) {
            url = candidate("\(base) \(suffix)")
            suffix += 1
        }
        return url
    }
}
