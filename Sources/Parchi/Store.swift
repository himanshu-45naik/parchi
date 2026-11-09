import AppKit
import ParchiCore
import Observation

struct DataPaths {
    let root: URL

    var database: URL { root.appendingPathComponent("parchi.sqlite") }
    var photos: URL { root.appendingPathComponent("photos", isDirectory: true) }
    var settings: URL { root.appendingPathComponent("settings.json") }

    static func resolve() throws -> DataPaths {
        let root: URL
        if let override = ProcessInfo.processInfo.environment["PARCHI_DATA_DIR"], !override.isEmpty {
            root = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            root = try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Parchi", isDirectory: true)
        }
        let paths = DataPaths(root: root)
        try FileManager.default.createDirectory(at: paths.photos, withIntermediateDirectories: true)
        return paths
    }
}

/// One live item. Each window observes only its own model, so typing in one note
/// does not redraw the others.
@Observable
final class ItemModel: Identifiable {
    let id: String
    var item: Item

    init(item: Item) {
        id = item.id
        self.item = item
    }
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case notes, todos, photos, archive, trash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notes: return "Notes"
        case .todos: return "To-dos"
        case .photos: return "Photos"
        case .archive: return "Archive"
        case .trash: return "Trash"
        }
    }

    var symbol: String {
        switch self {
        case .notes: return "note.text"
        case .todos: return "checklist"
        case .photos: return "photo"
        case .archive: return "archivebox"
        case .trash: return "trash"
        }
    }

    func contains(_ item: Item) -> Bool {
        switch self {
        case .notes: return item.state == .active && item.kind == .note
        case .todos: return item.state == .active && item.kind == .todo
        case .photos: return item.state == .active && item.kind == .photo
        case .archive: return item.state == .archived
        case .trash: return item.state == .trashed
        }
    }

    static func section(for item: Item) -> SidebarSection {
        allCases.first { $0.contains(item) } ?? .notes
    }
}

@Observable
final class Store {
    private(set) var models: [ItemModel] = []

    @ObservationIgnored let paths: DataPaths
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let database: NoteDatabase
    @ObservationIgnored private var dirty = Set<String>()
    @ObservationIgnored private var flushScheduled = false
    @ObservationIgnored private var cascadeIndex = 0
    @ObservationIgnored private var saveErrorShown = false

    /// Called after an item is created or changed. The old value is nil for a new item.
    @ObservationIgnored var onChange: ((ItemModel, Item?) -> Void)?
    @ObservationIgnored var onRemove: ((String) -> Void)?
    @ObservationIgnored var onSaveError: ((Error) -> Void)?

    init(paths: DataPaths, settings: AppSettings) throws {
        self.paths = paths
        self.settings = settings
        database = try NoteDatabase(path: paths.database.path)
        models = try database.allItems().map(ItemModel.init)
    }

    func model(id: String?) -> ItemModel? {
        guard let id else { return nil }
        return models.first { $0.id == id }
    }

    // MARK: Creating

    @discardableResult
    func createNote(title: String = "", text: String = "") -> ItemModel {
        var item = Item(kind: .note)
        item.title = title
        item.body = text
        applyDefaults(to: &item, onDesktop: settings.values.showNotesOnDesktop)
        item.frame = ItemFrame(nextFrame(size: CGSize(width: 290, height: 170)))
        return insert(item)
    }

    @discardableResult
    func createTodo(title: String = "", items: [String] = []) -> ItemModel {
        var item = Item(kind: .todo)
        item.title = title
        item.tasks = items.isEmpty ? [TodoTask()] : items.map { TodoTask(text: $0) }
        applyDefaults(to: &item, onDesktop: settings.values.showNotesOnDesktop)
        item.frame = ItemFrame(nextFrame(size: CGSize(width: 290, height: 210)))
        return insert(item)
    }

    @discardableResult
    func addPhoto(from url: URL) throws -> ItemModel {
        let imported = try PhotoLibrary.importPhoto(from: url, into: paths.photos)
        var item = Item(kind: .photo)
        item.photoFile = imported.file
        item.photoAspect = imported.aspect
        item.onDesktop = settings.values.showPhotosOnDesktop
        let width: CGFloat = 280
        let height = WindowPlacement.photoHeight(width: width, aspect: imported.aspect, look: item.photoLook)
        item.frame = ItemFrame(nextFrame(size: CGSize(width: width, height: height)))
        return insert(item)
    }

    private func applyDefaults(to item: inout Item, onDesktop: Bool) {
        let values = settings.values
        item.themeID = values.defaultThemeID
        item.fontFamily = values.defaultFontFamily
        item.fontSize = values.defaultFontSize
        item.onDesktop = onDesktop
    }

    private func nextFrame(size: CGSize) -> CGRect {
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        defer { cascadeIndex += 1 }
        return WindowPlacement.cascade(index: cascadeIndex, size: size, in: visible)
    }

    private func insert(_ item: Item) -> ItemModel {
        let model = ItemModel(item: item)
        models.insert(model, at: 0)
        markDirty(model.id)
        onChange?(model, nil)
        return model
    }

    // MARK: Changing

    /// Applies a change and schedules a save. `touch` is false for changes that are not
    /// edits to the content, such as moving a window.
    func update(_ model: ItemModel, touch: Bool = true, _ change: (inout Item) -> Void) {
        let old = model.item
        var new = old
        change(&new)
        guard new != old else { return }
        if touch { new.updatedAt = Date() }
        model.item = new
        markDirty(model.id)
        onChange?(model, old)
    }

    func setState(_ model: ItemModel, _ state: ItemState) {
        update(model) { item in
            item.state = state
            item.trashedAt = state == .trashed ? Date() : nil
        }
    }

    func deletePermanently(_ targets: [ItemModel]) {
        guard !targets.isEmpty else { return }
        let ids = Set(targets.map(\.id))
        do {
            try database.delete(ids: Array(ids))
        } catch {
            report(error)
            return
        }
        dirty.subtract(ids)
        for target in targets {
            if let file = target.item.photoFile {
                try? FileManager.default.removeItem(at: paths.photos.appendingPathComponent(file))
            }
        }
        models.removeAll { ids.contains($0.id) }
        ids.forEach { onRemove?($0) }
    }

    func purgeExpiredTrash() {
        let expired = Set(Retention.expired(models.map(\.item)).map(\.id))
        deletePermanently(models.filter { expired.contains($0.id) })
    }

    // MARK: Saving

    private func markDirty(_ id: String) {
        dirty.insert(id)
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self else { return }
            self.flushScheduled = false
            do {
                try self.flush()
            } catch {
                self.report(error)
            }
        }
    }

    /// Writes all unsaved changes now. Unsaved items stay marked if this fails.
    func flush() throws {
        guard !dirty.isEmpty else { return }
        let items = models.filter { dirty.contains($0.id) }.map(\.item)
        try database.save(items)
        dirty.removeAll()
        saveErrorShown = false
    }

    private func report(_ error: Error) {
        guard !saveErrorShown else { return }
        saveErrorShown = true
        onSaveError?(error)
    }

    // MARK: Reading

    func count(in section: SidebarSection) -> Int {
        models.reduce(0) { $0 + (section.contains($1.item) ? 1 : 0) }
    }

    func items(in section: SidebarSection, search: String, themeID: String?) -> [ItemModel] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return models.filter { model in
            let item = model.item
            guard section.contains(item) else { return false }
            if let themeID, item.themeID != themeID { return false }
            return query.isEmpty || item.searchableText.localizedStandardContains(query)
        }
    }
}
