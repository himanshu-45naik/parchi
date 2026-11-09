import AppKit
import ParchiCore
import SwiftUI

struct MainView: View {
    let services: AppServices

    var body: some View {
        NavigationSplitView {
            SidebarColumn(services: services)
                .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 240)
        } content: {
            ItemListColumn(services: services)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 400)
        } detail: {
            DetailColumn(services: services)
        }
        .tint(Brand.marigold)
    }
}

private struct SidebarColumn: View {
    let services: AppServices

    var body: some View {
        let router = services.router
        List(selection: Binding<SidebarSection?>(
            get: { router.section },
            set: { section in
                guard let section, section != router.section else { return }
                router.section = section
                router.selectedID = nil
            }
        )) {
            ForEach(SidebarSection.allCases) { section in
                Label(section.title, systemImage: section.symbol)
                    .badge(services.store.count(in: section))
                    .tag(section)
            }
        }
        .listStyle(.sidebar)
    }
}

private struct ItemListColumn: View {
    let services: AppServices

    var body: some View {
        @Bindable var router = services.router
        let items = services.store.items(in: router.section, search: router.search, themeID: router.themeFilter)

        VStack(spacing: 0) {
            header(router: router)
            Divider()

            if items.isEmpty {
                ContentUnavailableView(emptyTitle(router), systemImage: router.section.symbol)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(items, selection: $router.selectedID) { model in
                    ItemRow(model: model, services: services)
                        .tag(model.id)
                        .contextMenu { contextMenu(model) }
                }
                .listStyle(.inset)
            }

            if router.section == .trash, !items.isEmpty {
                Divider()
                HStack {
                    Text("Deleted after \(Retention.trashDays) days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Empty Trash") {
                        services.confirmDelete(items)
                    }
                    .controlSize(.small)
                }
                .padding(8)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let images = urls.filter { url in
                (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .image)) == true
            }
            services.addPhotos(images)
            return !images.isEmpty
        }
    }

    private func header(router: Router) -> some View {
        @Bindable var router = router
        return HStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $router.search)
                    .textFieldStyle(.plain)
                if !router.search.isEmpty {
                    Button {
                        router.search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            Menu {
                Button("All Themes") { router.themeFilter = nil }
                Divider()
                ForEach(CardTheme.all) { theme in
                    Button(theme.name) { router.themeFilter = theme.id }
                }
            } label: {
                Image(systemName: router.themeFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Filter by theme")

            Menu {
                Button("New Note") { services.newNote() }
                Button("New To-do List") { services.newTodo() }
                Button("Add Photo…") { services.choosePhotos() }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Add")
        }
        .padding(8)
    }

    private func emptyTitle(_ router: Router) -> String {
        if !router.search.isEmpty || router.themeFilter != nil { return "No matches" }
        switch router.section {
        case .notes: return "No notes yet"
        case .todos: return "No to-do lists yet"
        case .photos: return "No photos yet"
        case .archive: return "Nothing archived"
        case .trash: return "Trash is empty"
        }
    }

    @ViewBuilder
    private func contextMenu(_ model: ItemModel) -> some View {
        let store = services.store
        switch model.item.state {
        case .active:
            Button(model.item.onDesktop ? "Hide from Desktop" : "Show on Desktop") {
                store.update(model, touch: false) { $0.onDesktop.toggle() }
            }
            Button("Archive") { store.setState(model, .archived) }
            Button("Move to Trash") { store.setState(model, .trashed) }
        case .archived:
            Button("Unarchive") { store.setState(model, .active) }
            Button("Move to Trash") { store.setState(model, .trashed) }
        case .trashed:
            Button("Restore") { store.setState(model, .active) }
            Button("Delete Now") { services.confirmDelete([model]) }
        }
    }
}

private struct ItemRow: View {
    let model: ItemModel
    let services: AppServices

    var body: some View {
        let item = model.item
        HStack(spacing: 9) {
            if item.kind == .photo {
                let image = PhotoLibrary.image(file: item.photoFile, folder: services.store.paths.photos, maxPixel: 120)
                Group {
                    if let image {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.gray.opacity(0.3)
                    }
                }
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(CardTheme.find(item.themeID).color)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(.primary.opacity(0.2))
                    )
                    .frame(width: 12, height: 34)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(item.snippet.isEmpty ? item.createdAt.formatted(date: .abbreviated, time: .omitted) : item.snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if item.pinned {
                Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary)
            }
            if !item.onDesktop, item.state == .active {
                Image(systemName: "eye.slash").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct DetailColumn: View {
    let services: AppServices

    var body: some View {
        if let model = services.store.model(id: services.router.selectedID) {
            ItemDetail(model: model, services: services)
                .id(model.id)
        } else {
            ContentUnavailableView("Nothing selected", systemImage: "note.text")
        }
    }
}

private struct ItemDetail: View {
    let model: ItemModel
    let services: AppServices

    @State private var rich = RichTextController()

    var body: some View {
        HStack(spacing: 0) {
            editor
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            Inspector(model: model, services: services)
                .frame(width: 280)
        }
    }

    @ViewBuilder
    private var editor: some View {
        let item = model.item
        let theme = CardTheme.find(item.themeID)
        if item.kind == .photo {
            VStack(spacing: 12) {
                let image = PhotoLibrary.image(file: item.photoFile, folder: services.store.paths.photos, maxPixel: 1400)
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    ContentUnavailableView("Photo file is missing", systemImage: "photo.badge.exclamationmark")
                }
                TextField("Caption", text: Binding(
                    get: { model.item.title },
                    set: { text in services.store.update(model) { $0.title = text } }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
            }
            .padding(24)
        } else {
            ZStack(alignment: .bottomLeading) {
                ThemeBackground(theme: theme, decorated: false)
                VStack(spacing: 8) {
                    TitleField(model: model, store: services.store)
                        .padding(.horizontal, CardMetrics.horizontalPadding)
                        .padding(.top, CardMetrics.topPadding)
                    if item.kind == .note {
                        NoteBodyEditor(model: model, item: item, store: services.store, controller: rich)
                            .padding(.horizontal, CardMetrics.horizontalPadding)
                            .padding(.bottom, 30)
                    } else {
                        TodoEditor(model: model, services: services)
                            .padding(.bottom, 8)
                    }
                }
                if item.kind == .note {
                    FormatBar(controller: rich, theme: theme)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: CardMetrics.popupCornerRadius, style: .continuous))
            // The note's own theme decides light or dark, not the system's appearance.
            .environment(\.colorScheme, theme.isDark ? .dark : .light)
            .padding(20)
        }
    }
}

private struct Inspector: View {
    let model: ItemModel
    let services: AppServices

    private var store: Store { services.store }

    private func binding<Value: Equatable>(_ path: WritableKeyPath<Item, Value>) -> Binding<Value> {
        nonisolated(unsafe) let path = path
        return Binding(
            get: { model.item[keyPath: path] },
            set: { value in store.update(model, touch: false) { $0[keyPath: path] = value } }
        )
    }

    var body: some View {
        let item = model.item
        Form {
            if item.state == .active {
                Section("Desktop") {
                    Toggle("Show on desktop", isOn: binding(\.onDesktop))
                    Toggle("Keep above other windows", isOn: binding(\.pinned))
                    Picker("Spaces", selection: binding(\.allSpaces)) {
                        Text("All Spaces").tag(true)
                        Text("Current Space").tag(false)
                    }
                    HStack {
                        Text("Opacity")
                        Slider(value: binding(\.opacity), in: 0.2...1)
                    }
                }
            }

            if item.kind != .photo {
                Section("Theme") {
                    themeGrid(selected: item.themeID)
                }
                Section("Text") {
                    Picker("Font", selection: binding(\.fontFamily)) {
                        Text("Theme's own").tag(String?.none)
                        Divider()
                        ForEach(FontChoices.all, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                    Stepper("Size: \(Int(item.fontSize))", value: binding(\.fontSize), in: 10...48)
                }
            } else {
                Section("Photo") {
                    Picker("Look", selection: binding(\.photoLook)) {
                        ForEach(PhotoLook.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                }
            }

            Section {
                actions(state: item.state)
            }
        }
        .formStyle(.grouped)
    }

    private func themeGrid(selected: String) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 10) {
            ForEach(CardTheme.all) { theme in
                Button {
                    store.update(model, touch: false) { $0.themeID = theme.id }
                } label: {
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(theme.color)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(selected == theme.id ? Brand.marigold : Color.primary.opacity(0.2), lineWidth: selected == theme.id ? 2 : 1)
                            )
                            .frame(height: 34)
                        Text(theme.name)
                            .font(.caption2)
                            .foregroundStyle(.primary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(theme.name)
            }
        }
    }

    @ViewBuilder
    private func actions(state: ItemState) -> some View {
        switch state {
        case .active:
            Button("Archive") { store.setState(model, .archived) }
            Button("Move to Trash", role: .destructive) { store.setState(model, .trashed) }
        case .archived:
            Button("Unarchive") { store.setState(model, .active) }
            Button("Move to Trash", role: .destructive) { store.setState(model, .trashed) }
        case .trashed:
            Button("Restore") { store.setState(model, .active) }
            Button("Delete Now", role: .destructive) { services.confirmDelete([model]) }
        }
    }
}
