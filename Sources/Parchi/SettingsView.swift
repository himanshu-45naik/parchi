import AppKit
import ParchiCore
import ServiceManagement
import SwiftUI

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

struct SettingsView: View {
    let services: AppServices

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        @Bindable var settings = services.settings
        Form {
            Section("App") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                // At least one icon has to stay, or the app could only be reached by shortcut.
                Toggle("Show icon in Dock", isOn: $settings.values.showDockIcon)
                    .disabled(settings.values.showDockIcon && !settings.values.showMenuBarIcon)
                Toggle("Show icon in menu bar", isOn: $settings.values.showMenuBarIcon)
                    .disabled(settings.values.showMenuBarIcon && !settings.values.showDockIcon)
            }

            Section("Desktop") {
                Toggle("Show new notes on desktop", isOn: $settings.values.showNotesOnDesktop)
                Toggle("Show new photos on desktop", isOn: $settings.values.showPhotosOnDesktop)
                Toggle("Show shadows", isOn: $settings.values.showShadows)
            }

            Section("New notes") {
                Picker("Theme", selection: $settings.values.defaultThemeID) {
                    ForEach(CardTheme.all) { Text($0.name).tag($0.id) }
                }
                Picker("Font", selection: $settings.values.defaultFontFamily) {
                    Text("System").tag(String?.none)
                    Divider()
                    ForEach(FontChoices.all, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                Stepper("Text size: \(Int(settings.values.defaultFontSize))", value: $settings.values.defaultFontSize, in: 10...48)
                Toggle("Move completed to-dos to the bottom", isOn: $settings.values.moveCompletedToBottom)
            }

            Section("Global shortcuts") {
                ForEach(HotKeyAction.allCases) { action in
                    ShortcutRow(action: action, services: services)
                }
            }

            Section("Data") {
                Picker("Export format", selection: $settings.values.exportFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Toggle("Include archived notes", isOn: $settings.values.exportIncludeArchived)
                Button("Export Notes…") { services.exportNotes() }
                Button("Show Data Folder in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([services.store.paths.root])
                }
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.set(enabled)
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = LoginItem.isEnabled
    }
}

private struct ShortcutRow: View {
    let action: HotKeyAction
    let services: AppServices

    @State private var recording = false
    @State private var monitor: Any?
    @State private var message: String?

    var body: some View {
        let combo = services.settings.values.shortcuts[action.rawValue]
        VStack(alignment: .trailing, spacing: 2) {
            HStack {
                Text(action.label)
                Spacer()
                Button(recording ? "Press keys…" : (combo?.label ?? "Not set")) {
                    recording ? stop() : start()
                }
                if combo != nil, !recording {
                    Button {
                        services.settings.values.shortcuts[action.rawValue] = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Turn off this shortcut")
                }
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        message = nil
        // Otherwise pressing a shortcut that is already set would run it.
        services.hotKeys.unregisterAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func handle(_ event: NSEvent) {
        if Int(event.keyCode) == 53 { // Escape
            stop()
            return
        }
        guard let combo = KeyNames.combo(from: event) else {
            message = "Use at least one of ⌘, ⌃ or ⌥."
            return
        }
        var shortcuts = services.settings.values.shortcuts
        shortcuts[action.rawValue] = combo
        services.settings.values.shortcuts = shortcuts
        stop()
        if services.hotKeys.failed.contains(action) {
            message = "Another app is already using this shortcut."
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard recording else { return }
        recording = false
        services.hotKeys.register(services.settings.values.shortcuts)
    }
}
