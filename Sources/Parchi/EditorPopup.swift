import AppKit
import ParchiCore
import SwiftUI

/// The one place a desktop note gets edited. Opens beside the card and closes on
/// Done, Esc, or a click anywhere else.
final class EditorPopup: NSObject, NSWindowDelegate {
    private unowned let services: AppServices
    private(set) var panel: NotePanel?
    private(set) var model: ItemModel?

    init(services: AppServices) {
        self.services = services
    }

    func open(_ target: ItemModel) {
        if model?.id == target.id, let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        close()

        let screens = NSScreen.screens.map(\.visibleFrame)
        let anchor = services.windows.controller(for: target.id)?.panel.frame
            ?? NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let frame = WindowPlacement.popupFrame(anchor: anchor, size: Self.size(for: target.item), screens: screens)

        let panel = NotePanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = false
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace, .ignoresCycle]
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.close() }

        let view = EditorPopupView(model: target, services: services) { [weak self] in self?.close() }
        let host = NoteHostingView(rootView: view)
        host.sizingOptions = []
        panel.contentView = host

        self.panel = panel
        model = target

        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        model = nil
        panel.delegate = nil
        retireWindow(panel)
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    private static func size(for item: Item) -> CGSize {
        switch item.kind {
        case .note:
            return CGSize(width: 380, height: 340)
        case .todo:
            return CGSize(width: 360, height: 400)
        case .photo:
            let aspect = max(CGFloat(item.photoAspect ?? 1), 0.1)
            let width: CGFloat = aspect >= 1 ? 440 : 340
            return CGSize(width: width, height: min(width / aspect + 92, 680))
        }
    }
}

private struct EditorPopupView: View {
    let model: ItemModel
    let services: AppServices
    let close: () -> Void

    @State private var rich = RichTextController()

    var body: some View {
        let item = model.item
        let theme = CardTheme.find(item.themeID)
        Group {
            if item.kind == .photo {
                photoEditor(item)
            } else {
                textEditor(item, theme: theme)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: CardMetrics.popupCornerRadius, style: .continuous))
        .environment(\.colorScheme, item.kind != .photo && theme.isDark ? .dark : .light)
    }

    private func textEditor(_ item: Item, theme: CardTheme) -> some View {
        ZStack {
            ThemeBackground(theme: theme, decorated: false)

            VStack(alignment: .leading, spacing: 0) {
                DragRegion()
                    .frame(height: CardMetrics.topPadding)

                TitleField(model: model, store: services.store)
                    .padding(.horizontal, CardMetrics.horizontalPadding)
                    .padding(.bottom, CardMetrics.titleGap)

                if item.kind == .note {
                    NoteBodyEditor(model: model, item: item, store: services.store, controller: rich)
                        .padding(.horizontal, CardMetrics.horizontalPadding)
                } else {
                    TodoEditor(model: model, services: services, autoFocus: true)
                }

                HStack(spacing: 2) {
                    if item.kind == .note {
                        FormatBar(controller: rich, theme: theme)
                    }
                    Spacer(minLength: 0)
                    IconButton(symbol: "ellipsis", help: "More", ink: theme.inkColor) {
                        popUpMenu(services.moreMenuItems(for: model))
                    }
                    doneButton(background: theme.inkColor, text: theme.color)
                        .padding(.leading, 4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .onAppear {
            if item.kind == .note { rich.focus() }
        }
    }

    private func photoEditor(_ item: Item) -> some View {
        let ink = Color(nsColor: Brand.ink)
        return VStack(spacing: 10) {
            Group {
                if let image = PhotoLibrary.image(file: item.photoFile, folder: services.store.paths.photos, maxPixel: 1400) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    ContentUnavailableView("Photo file is missing", systemImage: "photo.badge.exclamationmark")
                }
            }
            .overlay(DragRegion())

            if item.photoLook.showsCaption {
                TextField("Add a caption", text: Binding(
                    get: { model.item.title },
                    set: { text in services.store.update(model) { $0.title = text } }
                ))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .foregroundStyle(ink)
            }

            HStack(spacing: 2) {
                Spacer(minLength: 0)
                IconButton(symbol: "ellipsis", help: "More", ink: ink) {
                    popUpMenu(services.moreMenuItems(for: model))
                }
                doneButton(background: ink, text: Color(nsColor: Brand.paper))
                    .padding(.leading, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: Brand.paper))
    }

    private func doneButton(background: Color, text: Color) -> some View {
        Button(action: close) {
            Text("Done")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .frame(height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(text)
        .background(background, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .help("Close (Esc)")
    }
}
