import AppKit
import ParchiCore
import SwiftUI

enum CardMetrics {
    static let horizontalPadding: CGFloat = 24
    static let topPadding: CGFloat = 22
    static let titleGap: CGFloat = 10
    static let titleSizeBoost: CGFloat = 3
    static let popupCornerRadius: CGFloat = 12
}

/// A note as it appears on the desktop: a finished slip of paper that shows its content.
/// Editing happens in `EditorPopup`.
struct DesktopItemView: View {
    let model: ItemModel
    let services: AppServices
    let chrome: WindowChrome

    var body: some View {
        let item = model.item
        if item.kind == .photo {
            ZStack {
                PhotoContent(
                    image: PhotoLibrary.image(file: item.photoFile, folder: services.store.paths.photos, maxPixel: 1400),
                    item: item
                )
                .allowsHitTesting(false)
                interaction
                CardControls(model: model, item: item, services: services, chrome: chrome)
            }
        } else {
            let theme = CardTheme.find(item.themeID)
            ZStack {
                ThemeBackground(theme: theme)
                if theme.edge == .slip {
                    FoldCorner(color: theme.fold)
                }
                interaction
                CardContent(model: model, item: item, theme: theme, services: services, chrome: chrome)
                CardControls(model: model, item: item, services: services, chrome: chrome)
            }
            .clipShape(theme.edge == .torn ? AnyShape(TornShape()) : AnyShape(SlipShape()))
        }
    }

    private var interaction: some View {
        CardInteraction(
            onClick: { services.editor.open(model) },
            onScroll: { chrome.scrollBy($0) }
        )
    }
}

/// Text and tasks on a card. Everything except the checkboxes lets the mouse through to
/// `CardInteraction` underneath, which is what makes the whole card draggable.
private struct CardContent: View {
    let model: ItemModel
    let item: Item
    let theme: CardTheme
    let services: AppServices
    let chrome: WindowChrome
    /// Parsed once per change to the item rather than on every scroll step.
    private let bodyText: NSAttributedString?

    init(model: ItemModel, item: Item, theme: CardTheme, services: AppServices, chrome: WindowChrome) {
        self.model = model
        self.item = item
        self.theme = theme
        self.services = services
        self.chrome = chrome
        bodyText = item.kind == .note && !item.body.isEmpty ? NoteFont.attributedBody(item, forCard: true) : nil
    }

    private var tasks: [TodoTask] {
        TodoOrdering.display(
            item.tasks.filter { !$0.text.isEmpty },
            completedLast: services.settings.values.moveCompletedToBottom
        )
    }

    private var title: String { item.title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isEmpty: Bool {
        title.isEmpty && (item.kind == .note ? item.body.isEmpty : tasks.isEmpty)
    }

    /// Notebook lines leave no room for a gap: every row sits on its own rule.
    private var titleGap: CGFloat { theme.lineHeight == nil ? CardMetrics.titleGap : 0 }

    var body: some View {
        GeometryReader { proxy in
            let insets = theme.insets
            let width = max(proxy.size.width - insets.leading - insets.trailing, 20)
            let maximum = max(chrome.contentHeight + insets.top + insets.bottom - proxy.size.height, 0)

            VStack(alignment: .leading, spacing: titleGap) {
                if !title.isEmpty {
                    titleView
                }

                if let bodyText {
                    RichTextDisplay(text: bodyText)
                        .frame(width: width, height: RichTextDisplay.height(of: bodyText, width: width))
                        .allowsHitTesting(false)
                }

                if item.kind == .todo, !tasks.isEmpty {
                    taskList
                }

                if isEmpty {
                    Text(item.kind == .note ? "Empty note" : "Empty to-do list")
                        .font(Font(NoteFont.body(item) as CTFont))
                        .foregroundStyle(theme.inkColor.opacity(0.45))
                        .allowsHitTesting(false)
                }
            }
            .frame(width: width, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { chrome.contentHeight = $0 }
            .padding(.leading, insets.leading)
            .padding(.top, insets.top)
            .offset(y: -min(chrome.scroll, maximum))
            .onChange(of: maximum, initial: true) { _, value in chrome.maxScroll = value }
        }
    }

    private var titleView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(theme.edge == .torn ? title.uppercased() : title)
                .font(Font(NoteFont.title(item) as CTFont))
                .foregroundStyle(Color(nsColor: theme.titleColor ?? theme.ink))
                .frame(minHeight: theme.lineHeight ?? 0, alignment: .leading)

            if theme.edge == .torn {
                Line()
                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .foregroundStyle(Color(nsColor: NSColor(hex: 0x8C877A)))
                    .frame(height: 1.5)
            }
        }
        .allowsHitTesting(false)
    }

    private var taskList: some View {
        let font = Font(NoteFont.body(item) as CTFont)
        let ink = theme.inkColor
        let size = CGFloat(item.fontSize)
        return VStack(alignment: .leading, spacing: theme.lineHeight == nil ? 7 : 0) {
            ForEach(tasks) { task in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Button {
                        services.store.update(model) { item in
                            guard let index = item.tasks.firstIndex(where: { $0.id == task.id }) else { return }
                            item.tasks[index].done.toggle()
                        }
                    } label: {
                        Image(systemName: Self.checkSymbol(done: task.done, square: theme.squareChecks))
                            .font(.system(size: size))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ink.opacity(task.done ? 0.55 : 0.85))
                    .help(task.done ? "Mark as not done" : "Mark as done")

                    Text(task.text)
                        .font(font)
                        .strikethrough(task.done, color: ink.opacity(0.6))
                        .foregroundStyle(ink.opacity(task.done ? 0.6 : 1))
                        .allowsHitTesting(false)
                }
                .frame(minHeight: theme.lineHeight ?? 0, alignment: .leading)
            }
        }
    }

    static func checkSymbol(done: Bool, square: Bool) -> String {
        if square { return done ? "checkmark.square" : "square" }
        return done ? "checkmark.circle.fill" : "circle"
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// The button bar. Shown only while the pointer is over the card, so the card stays clean.
private struct CardControls: View {
    let model: ItemModel
    let item: Item
    let services: AppServices
    let chrome: WindowChrome

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear.allowsHitTesting(false)
            if chrome.hovering {
                bar
                    .padding(.bottom, 10)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: chrome.hovering)
    }

    private var theme: CardTheme { CardTheme.find(item.themeID) }

    /// The bar is the card's colors swapped, so it stands out on every theme.
    private var barColor: Color { Color(nsColor: item.kind == .photo ? Brand.ink : theme.ink) }
    private var iconColor: Color { Color(nsColor: item.kind == .photo ? Brand.paper : theme.surface) }

    private var bar: some View {
        HStack(spacing: 2) {
            IconButton(symbol: "plus", help: "Add", active: true, ink: iconColor) {
                popUpMenu(services.addMenuItems())
            }
            IconButton(
                symbol: item.pinned ? "pin.fill" : "pin",
                help: item.pinned ? "Unpin" : "Keep above other windows",
                active: true,
                ink: iconColor
            ) {
                services.store.update(model, touch: false) { $0.pinned.toggle() }
            }
            IconButton(symbol: "eye.slash", help: "Hide from desktop", active: true, ink: iconColor) {
                services.store.update(model, touch: false) { $0.onDesktop = false }
            }
            IconButton(symbol: "ellipsis", help: "More", active: true, ink: iconColor) {
                popUpMenu(services.moreMenuItems(for: model))
            }
            IconButton(symbol: "trash", help: "Move to Trash", active: true, ink: iconColor) {
                services.store.setState(model, .trashed)
            }
        }
        .padding(5)
        .background(barColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct TitleField: View {
    let model: ItemModel
    let store: Store

    var body: some View {
        let item = model.item
        let theme = CardTheme.find(item.themeID)
        TextField("Title", text: Binding(
            get: { model.item.title },
            set: { text in store.update(model) { $0.title = text } }
        ), prompt: Text("Title").foregroundStyle(theme.inkColor.opacity(0.4)))
        .textFieldStyle(.plain)
        .font(Font(NoteFont.title(item) as CTFont))
        .foregroundStyle(Color(nsColor: theme.titleColor ?? theme.ink))
    }
}

struct NoteBodyEditor: View {
    let model: ItemModel
    let item: Item
    let store: Store
    let controller: RichTextController

    var body: some View {
        RichTextEditor(model: model, item: item, store: store, controller: controller)
            .overlay(alignment: .topLeading) {
                if item.body.isEmpty {
                    Text("Write something…")
                        .font(Font(NoteFont.body(item) as CTFont))
                        .foregroundStyle(CardTheme.find(item.themeID).inkColor.opacity(0.4))
                        .padding(.top, 2)
                        .allowsHitTesting(false)
                }
            }
    }
}
