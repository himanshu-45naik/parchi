import AppKit
import ParchiCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var services: AppServices?
    private var statusItem: NSStatusItem?
    private var pendingURLs: [URL] = []
    private var launched = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        do {
            services = try AppServices(paths: DataPaths.resolve())
        } catch {
            NSAlert(error: error).runModal()
            exit(1)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let services else { return }

        buildMainMenu()
        applyIcons()
        allowCursorChangesInBackground()

        services.settings.onChange = { [unowned self] old in
            self.settingsChanged(from: old)
        }
        services.hotKeys.handler = { [unowned services] action in
            services.perform(action)
        }
        services.hotKeys.register(services.settings.values.shortcuts)

        services.windows.syncAll()
        services.store.purgeExpiredTrash()
        Task { [weak services] in
            while let services {
                try? await Task.sleep(for: .seconds(3600))
                services.store.purgeExpiredTrash()
            }
        }

        if services.store.models.isEmpty {
            services.openMain()
        }

        launched = true
        pendingURLs.forEach(open)
        pendingURLs.removeAll()

        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let folder = environment["PARCHI_SELFTEST"] {
            Task {
                await SelfTest.run(
                    services: services,
                    folder: URL(fileURLWithPath: folder, isDirectory: true),
                    phase: environment["PARCHI_SELFTEST_PHASE"] ?? "first"
                )
            }
        }
        #endif
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if launched {
            urls.forEach(open)
        } else {
            pendingURLs += urls
        }
    }

    private func open(_ url: URL) {
        guard let command = URLCommand(url: url) else { return }
        services?.handle(command)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        services?.openMain()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        do {
            try services?.store.flush()
            return .terminateNow
        } catch {
            let alert = NSAlert()
            alert.messageText = "Parchi could not save your latest changes"
            alert.informativeText = "\(error.localizedDescription)\n\nQuitting now loses them."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Quit Anyway")
            return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
        }
    }

    // MARK: Settings

    private func settingsChanged(from old: SettingsValues) {
        guard let services else { return }
        let new = services.settings.values
        if new.showDockIcon != old.showDockIcon || new.showMenuBarIcon != old.showMenuBarIcon {
            applyIcons()
        }
        if new.showShadows != old.showShadows {
            services.windows.refreshAppearance()
        }
        if new.shortcuts != old.shortcuts {
            services.hotKeys.register(new.shortcuts)
        }
    }

    private func applyIcons() {
        guard let values = services?.settings.values else { return }
        NSApp.setActivationPolicy(values.showDockIcon ? .regular : .accessory)

        if values.showMenuBarIcon, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.image = ParchiMark.menuBarImage()
            item.menu = buildStatusMenu()
            statusItem = item
        } else if !values.showMenuBarIcon, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    // MARK: Menu actions

    @objc private func newNote() { services?.newNote() }
    @objc private func newTodo() { services?.newTodo() }
    @objc private func addPhoto() { services?.choosePhotos() }
    @objc private func openMain() { services?.openMain() }
    @objc private func openSettings() { services?.openSettings() }

    // MARK: Menus

    private func item(_ title: String, _ action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        return item
    }

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("New Note", #selector(newNote)))
        menu.addItem(item("New To-do List", #selector(newTodo)))
        menu.addItem(item("Add Photo…", #selector(addPhoto)))
        menu.addItem(.separator())
        menu.addItem(item("Open Main Window", #selector(openMain)))
        menu.addItem(item("Settings…", #selector(openSettings)))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Parchi", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        return menu
    }

    private func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        holder.submenu = menu
        return holder
    }

    /// An item with no target, so it goes to whatever has keyboard focus.
    private func standard(_ title: String, _ action: Selector, key: String, modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private func buildMainMenu() {
        let main = NSMenu()
        main.addItem(menu("Parchi", [
            standard("About Parchi", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), key: ""),
            .separator(),
            item("Settings…", #selector(openSettings), key: ","),
            .separator(),
            standard("Hide Parchi", #selector(NSApplication.hide(_:)), key: "h"),
            standard("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), key: "h", modifiers: [.command, .option]),
            standard("Show All", #selector(NSApplication.unhideAllApplications(_:)), key: ""),
            .separator(),
            standard("Quit Parchi", #selector(NSApplication.terminate(_:)), key: "q"),
        ]))
        main.addItem(menu("File", [
            item("New Note", #selector(newNote), key: "n"),
            item("New To-do List", #selector(newTodo), key: "n", modifiers: [.command, .shift]),
            item("Add Photo…", #selector(addPhoto), key: "p", modifiers: [.command, .shift]),
            .separator(),
            standard("Close", #selector(NSWindow.performClose(_:)), key: "w"),
        ]))
        main.addItem(menu("Edit", [
            standard("Undo", Selector(("undo:")), key: "z"),
            standard("Redo", Selector(("redo:")), key: "z", modifiers: [.command, .shift]),
            .separator(),
            standard("Cut", #selector(NSText.cut(_:)), key: "x"),
            standard("Copy", #selector(NSText.copy(_:)), key: "c"),
            standard("Paste", #selector(NSText.paste(_:)), key: "v"),
            standard("Select All", #selector(NSResponder.selectAll(_:)), key: "a"),
        ]))
        main.addItem(menu("Format", [
            standard("Bold", #selector(RichTextView.noteToggleBold(_:)), key: "b"),
            standard("Italic", #selector(RichTextView.noteToggleItalic(_:)), key: "i"),
            standard("Underline", #selector(RichTextView.noteToggleUnderline(_:)), key: "u"),
            standard("Strikethrough", #selector(RichTextView.noteToggleStrikethrough(_:)), key: "x", modifiers: [.command, .shift]),
        ]))
        let window = menu("Window", [
            standard("Minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m"),
            .separator(),
            item("Main Window", #selector(openMain), key: "0"),
        ])
        main.addItem(window)
        NSApp.mainMenu = main
        NSApp.windowsMenu = window.submenu
    }
}
