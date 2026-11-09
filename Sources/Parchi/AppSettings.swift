import Carbon.HIToolbox
import Foundation
import ParchiCore
import Observation

enum HotKeyAction: String, CaseIterable, Identifiable {
    case newNote, newTodo, openMain

    var id: String { rawValue }

    var hotKeyID: UInt32 {
        switch self {
        case .newNote: return 1
        case .newTodo: return 2
        case .openMain: return 3
        }
    }

    var label: String {
        switch self {
        case .newNote: return "New note"
        case .newTodo: return "New to-do list"
        case .openMain: return "Open main window"
        }
    }
}

nonisolated struct KeyCombo: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32
    var label: String

    static let defaults: [String: KeyCombo] = [
        "newNote": KeyCombo(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(controlKey | optionKey), label: "⌃⌥N"),
        "newTodo": KeyCombo(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | optionKey), label: "⌃⌥T"),
        "openMain": KeyCombo(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(controlKey | optionKey), label: "⌃⌥M"),
    ]
}

nonisolated struct SettingsValues: Codable, Equatable, Sendable {
    var showDockIcon = true
    var showMenuBarIcon = true
    var showNotesOnDesktop = true
    var showPhotosOnDesktop = true
    var showShadows = true
    var moveCompletedToBottom = true
    var defaultFontFamily: String?
    var defaultFontSize: Double = 16
    var defaultThemeID = "kagaz"
    var exportFormat: ExportFormat = .markdown
    var exportIncludeArchived = false
    /// Keyed by `HotKeyAction.rawValue`. A missing key means the shortcut is turned off.
    var shortcuts: [String: KeyCombo] = KeyCombo.defaults

    init() {}

    // Tolerant so that adding a setting later does not reset the others.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = SettingsValues()
        showDockIcon = try container.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? fallback.showDockIcon
        showMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? fallback.showMenuBarIcon
        showNotesOnDesktop = try container.decodeIfPresent(Bool.self, forKey: .showNotesOnDesktop) ?? fallback.showNotesOnDesktop
        showPhotosOnDesktop = try container.decodeIfPresent(Bool.self, forKey: .showPhotosOnDesktop) ?? fallback.showPhotosOnDesktop
        showShadows = try container.decodeIfPresent(Bool.self, forKey: .showShadows) ?? fallback.showShadows
        moveCompletedToBottom = try container.decodeIfPresent(Bool.self, forKey: .moveCompletedToBottom) ?? fallback.moveCompletedToBottom
        defaultFontFamily = try container.decodeIfPresent(String.self, forKey: .defaultFontFamily)
        defaultFontSize = try container.decodeIfPresent(Double.self, forKey: .defaultFontSize) ?? fallback.defaultFontSize
        defaultThemeID = try container.decodeIfPresent(String.self, forKey: .defaultThemeID) ?? fallback.defaultThemeID
        exportFormat = try container.decodeIfPresent(ExportFormat.self, forKey: .exportFormat) ?? fallback.exportFormat
        exportIncludeArchived = try container.decodeIfPresent(Bool.self, forKey: .exportIncludeArchived) ?? fallback.exportIncludeArchived
        shortcuts = try container.decodeIfPresent([String: KeyCombo].self, forKey: .shortcuts) ?? fallback.shortcuts
    }
}

@Observable
final class AppSettings {
    var values: SettingsValues {
        didSet {
            guard values != oldValue else { return }
            save()
            onChange?(oldValue)
        }
    }

    @ObservationIgnored var onChange: ((SettingsValues) -> Void)?
    @ObservationIgnored private let url: URL

    init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(SettingsValues.self, from: data) {
            values = decoded
        } else {
            values = SettingsValues()
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(values) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
