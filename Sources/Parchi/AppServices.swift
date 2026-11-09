import AppKit
import ParchiCore
import SwiftUI

@Observable
final class Router {
    var section: SidebarSection = .notes
    var selectedID: String?
    var search = ""
    var themeFilter: String?
}

/// Everything the views need, plus the actions shared by menus, shortcuts and URLs.
final class AppServices {
    let settings: AppSettings
    let store: Store
    let router = Router()
    let hotKeys = HotKeyCenter()
    private(set) lazy var windows = NoteWindowManager(services: self)
    private(set) lazy var editor = EditorPopup(services: self)

    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?

    init(paths: DataPaths) throws {
        settings = AppSettings(url: paths.settings)
        store = try Store(paths: paths, settings: settings)
        store.onChange = { [unowned self] model, old in
            self.windows.sync(model, old: old)
            if model.item.state != .active, self.editor.model?.id == model.id {
                self.editor.close()
            }
        }
        store.onRemove = { [unowned self] id in
            self.windows.remove(id: id)
            if self.editor.model?.id == id { self.editor.close() }
            if self.router.selectedID == id { self.router.selectedID = nil }
        }
        store.onSaveError = { error in
            showAlert("Parchi could not save your changes", detail: error.localizedDescription)
        }
    }

    // MARK: Creating

    func newNote(title: String = "", text: String = "") {
        // A note that arrives with content (from a URL) has nothing left to type.
        present(store.createNote(title: title, text: text), edit: title.isEmpty && text.isEmpty)
    }

    func newTodo(title: String = "", items: [String] = []) {
        present(store.createTodo(title: title, items: items), edit: items.isEmpty)
    }

    private func present(_ model: ItemModel, edit: Bool) {
        if model.item.onDesktop {
            windows.reveal(model)
            if edit { editor.open(model) }
        } else {
            openMain(selecting: model)
        }
    }

    func choosePhotos() {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        addPhotos(panel.urls)
    }

    func addPhotos(_ urls: [URL]) {
        var failed: [String] = []
        for url in urls {
            do {
                try store.addPhoto(from: url)
            } catch {
                failed.append(url.lastPathComponent)
            }
        }
        if !failed.isEmpty {
            showAlert("Some files could not be added", detail: failed.joined(separator: "\n"))
        }
    }

    func handle(_ command: URLCommand) {
        switch command {
        case let .newNote(title, text): newNote(title: title, text: text)
        case let .newTodo(title, items): newTodo(title: title, items: items)
        case .openMain: openMain()
        }
    }

    func perform(_ action: HotKeyAction) {
        switch action {
        case .newNote: newNote()
        case .newTodo: newTodo()
        case .openMain: openMain()
        }
    }

    // MARK: Windows

    func openMain(selecting model: ItemModel? = nil) {
        if mainWindow == nil {
            let controller = NSHostingController(rootView: MainView(services: self))
            controller.sizingOptions = []
            let window = NSWindow(contentViewController: controller)
            window.title = "Parchi"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 1060, height: 660))
            window.minSize = NSSize(width: 880, height: 520)
            window.isReleasedWhenClosed = false
            window.center()
            window.setFrameAutosaveName("MainWindow")
            mainWindow = window
        }
        if let model {
            router.search = ""
            router.themeFilter = nil
            router.section = SidebarSection.section(for: model.item)
            router.selectedID = model.id
        }
        NSApp.activate()
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    func openSettings() {
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView(services: self))
            controller.sizingOptions = []
            let window = NSWindow(contentViewController: controller)
            window.title = "Parchi Settings"
            window.styleMask = [.titled, .closable, .resizable]
            window.setContentSize(NSSize(width: 480, height: 640))
            window.minSize = NSSize(width: 420, height: 400)
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Data

    func exportNotes() {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        guard panel.runModal() == .OK, let parent = panel.url else { return }

        let values = settings.values
        let items = store.models.map(\.item).filter {
            $0.state == .active || (values.exportIncludeArchived && $0.state == .archived)
        }
        do {
            let result = try Exporter.export(items, format: values.exportFormat, into: parent)
            NSWorkspace.shared.activateFileViewerSelecting([result.folder])
            showAlert("Exported \(result.count) notes", detail: result.folder.path)
        } catch {
            showAlert("Export failed", detail: error.localizedDescription)
        }
    }

    func confirmDelete(_ targets: [ItemModel]) {
        guard !targets.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = targets.count == 1
            ? "Permanently delete this item?"
            : "Permanently delete \(targets.count) items?"
        alert.informativeText = "This can't be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            store.deletePermanently(targets)
        }
    }

    // MARK: Menus

    func addMenuItems() -> [NSMenuItem] {
        [
            actionItem("New Note") { [unowned self] in self.newNote() },
            actionItem("New To-do List") { [unowned self] in self.newTodo() },
            actionItem("Add Photo…") { [unowned self] in self.choosePhotos() },
        ]
    }

    func moreMenuItems(for model: ItemModel) -> [NSMenuItem] {
        let item = model.item
        var items: [NSMenuItem] = []

        if item.kind != .photo {
            items.append(submenu("Theme", CardTheme.all.map { theme in
                actionItem(theme.name, checked: item.themeID == theme.id, image: theme.surface.swatch()) { [unowned self] in
                    self.store.update(model, touch: false) { $0.themeID = theme.id }
                }
            }))

            var fonts: [NSMenuItem] = [
                actionItem("Theme's Own", checked: item.fontFamily == nil) { [unowned self] in
                    self.store.update(model, touch: false) { $0.fontFamily = nil }
                },
            ]
            fonts += FontChoices.suggested.map { family in
                actionItem(family, checked: item.fontFamily == family) { [unowned self] in
                    self.store.update(model, touch: false) { $0.fontFamily = family }
                }
            }
            items.append(submenu("Font", fonts))

            items.append(submenu("Text Size", [12.0, 13, 14, 15, 16, 18, 20, 24, 28].map { size in
                actionItem("\(Int(size))", checked: item.fontSize == size) { [unowned self] in
                    self.store.update(model, touch: false) { $0.fontSize = size }
                }
            }))
        } else {
            items.append(submenu("Look", PhotoLook.allCases.map { look in
                actionItem(look.name, checked: item.photoLook == look) { [unowned self] in
                    self.store.update(model, touch: false) { $0.photoLook = look }
                }
            }))
        }

        items.append(submenu("Opacity", [1.0, 0.9, 0.75, 0.6, 0.4].map { value in
            actionItem("\(Int(value * 100))%", checked: abs(item.opacity - value) < 0.01) { [unowned self] in
                self.store.update(model, touch: false) { $0.opacity = value }
            }
        }))
        items.append(actionItem("Show in All Spaces", checked: item.allSpaces) { [unowned self] in
            self.store.update(model, touch: false) { $0.allSpaces.toggle() }
        })

        items.append(.separator())
        items.append(actionItem("Open in Main Window") { [unowned self] in
            self.openMain(selecting: model)
        })
        items.append(actionItem("Archive") { [unowned self] in
            self.store.setState(model, .archived)
        })
        return items
    }
}

func showAlert(_ message: String, detail: String) {
    NSApp.activate()
    let alert = NSAlert()
    alert.messageText = message
    alert.informativeText = detail
    alert.runModal()
}
