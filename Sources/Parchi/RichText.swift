import AppKit
import ParchiCore
import SwiftUI

enum NoteFont {
    /// A chosen font family wins over the theme's own type.
    static func make(face: CardFace, family: String?, size: CGFloat, traits: NSFontTraitMask = []) -> NSFont {
        let manager = NSFontManager.shared
        let named = family ?? (face == .hand ? "Noteworthy" : nil)
        if let named, var font = manager.font(withFamily: named, traits: [], weight: 5, size: size) {
            if traits.contains(.boldFontMask) { font = manager.convert(font, toHaveTrait: .boldFontMask) }
            if traits.contains(.italicFontMask) { font = manager.convert(font, toHaveTrait: .italicFontMask) }
            return font
        }

        let bold = traits.contains(.boldFontMask)
        let weight: NSFont.Weight = bold ? (face == .rounded ? .heavy : .bold) : .regular
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        var descriptor = base.fontDescriptor
        if let design = face.design, let designed = descriptor.withDesign(design) {
            descriptor = designed
        }
        if traits.contains(.italicFontMask) {
            descriptor = descriptor.withSymbolicTraits(.italic)
        }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    static func body(_ item: Item, traits: NSFontTraitMask = []) -> NSFont {
        make(face: CardTheme.find(item.themeID).bodyFace, family: item.fontFamily, size: CGFloat(item.fontSize), traits: traits)
    }

    static func title(_ item: Item) -> NSFont {
        make(
            face: CardTheme.find(item.themeID).titleFace,
            family: item.fontFamily,
            size: CGFloat(item.fontSize) + CardMetrics.titleSizeBoost,
            traits: .boldFontMask
        )
    }

    /// Puts the note's font, size and ink on all text while keeping bold, italic and highlights.
    static func restyle(_ text: NSMutableAttributedString, item: Item) {
        let full = NSRange(location: 0, length: text.length)
        let ink = CardTheme.find(item.themeID).ink
        let manager = NSFontManager.shared

        text.beginEditing()
        text.enumerateAttribute(.font, in: full) { value, range, _ in
            let traits = (value as? NSFont).map { manager.traits(of: $0) } ?? []
            let kept = traits.intersection([.boldFontMask, .italicFontMask])
            text.addAttribute(.font, value: body(item, traits: kept), range: range)
        }
        text.addAttribute(.foregroundColor, value: ink, range: full)
        text.enumerateAttribute(.backgroundColor, in: full) { value, range, _ in
            if value != nil {
                text.addAttribute(.foregroundColor, value: Highlight.inkOnHighlight, range: range)
            }
        }
        text.endEditing()
    }

    /// A note's body as styled text, ready to show or edit.
    /// On a card, text in a lined theme is set to land on the printed lines.
    static func attributedBody(_ item: Item, forCard: Bool = false) -> NSMutableAttributedString {
        let text: NSMutableAttributedString
        if let data = item.richText,
           let parsed = try? NSMutableAttributedString(
               data: data,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ) {
            text = parsed
        } else {
            text = NSMutableAttributedString(string: item.body)
        }
        restyle(text, item: item)
        if forCard, let height = CardTheme.find(item.themeID).lineHeight {
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = height
            paragraph.maximumLineHeight = height
            text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))
        }
        return text
    }

    static func typingAttributes(item: Item) -> [NSAttributedString.Key: Any] {
        [
            .font: body(item),
            .foregroundColor: CardTheme.find(item.themeID).ink,
        ]
    }
}

final class RichTextView: NSTextView {
    /// Builds this note's font with the given bold and italic traits.
    var fontMaker: ((NSFontTraitMask) -> NSFont)?

    /// Pasted text takes the note's own style, so notes stay visually consistent.
    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }

    @objc func noteToggleBold(_ sender: Any?) { toggleTrait(.boldFontMask) }
    @objc func noteToggleItalic(_ sender: Any?) { toggleTrait(.italicFontMask) }
    @objc func noteToggleUnderline(_ sender: Any?) { toggleLine(.underlineStyle) }
    @objc func noteToggleStrikethrough(_ sender: Any?) { toggleLine(.strikethroughStyle) }

    private func toggleTrait(_ trait: NSFontTraitMask) {
        let manager = NSFontManager.shared
        let fallback = font ?? NSFont.systemFont(ofSize: 15)
        func converted(_ font: NSFont, removing: Bool) -> NSFont {
            var traits = manager.traits(of: font).intersection([.boldFontMask, .italicFontMask])
            if removing { traits.remove(trait) } else { traits.insert(trait) }
            return fontMaker?(traits) ?? font
        }

        let range = selectedRange()
        guard range.length > 0, let storage = textStorage else {
            let current = typingAttributes[.font] as? NSFont ?? fallback
            typingAttributes[.font] = converted(current, removing: manager.traits(of: current).contains(trait))
            return
        }
        guard shouldChangeText(in: range, replacementString: nil) else { return }
        let first = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? fallback
        let removing = manager.traits(of: first).contains(trait)
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, run, _ in
            storage.addAttribute(.font, value: converted(value as? NSFont ?? fallback, removing: removing), range: run)
        }
        storage.endEditing()
        didChangeText()
    }

    private func toggleLine(_ key: NSAttributedString.Key) {
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage else {
            let isOn = (typingAttributes[key] as? Int ?? 0) != 0
            typingAttributes[key] = isOn ? nil : NSUnderlineStyle.single.rawValue
            return
        }
        guard shouldChangeText(in: range, replacementString: nil) else { return }
        let isOn = (storage.attribute(key, at: range.location, effectiveRange: nil) as? Int ?? 0) != 0
        if isOn {
            storage.removeAttribute(key, range: range)
        } else {
            storage.addAttribute(key, value: NSUnderlineStyle.single.rawValue, range: range)
        }
        didChangeText()
    }

    /// Highlights the selection, or clears its highlight when `color` is nil.
    func applyHighlight(_ color: NSColor?, ink: NSColor) {
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage,
              shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        if let color {
            storage.addAttribute(.backgroundColor, value: color, range: range)
            storage.addAttribute(.foregroundColor, value: Highlight.inkOnHighlight, range: range)
        } else {
            storage.removeAttribute(.backgroundColor, range: range)
            storage.addAttribute(.foregroundColor, value: ink, range: range)
        }
        storage.endEditing()
        didChangeText()
    }
}

/// Lets toolbar buttons reach the text view of the editor next to them.
final class RichTextController {
    weak var textView: RichTextView?

    func focus() {
        guard let textView else { return }
        Task { @MainActor in
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
        }
    }
}

struct RichTextEditor: NSViewRepresentable {
    let model: ItemModel
    /// Passed so that this view updates whenever the item changes.
    let item: Item
    let store: Store
    let controller: RichTextController

    func makeCoordinator() -> Coordinator { Coordinator(model: model, store: store) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = RichTextView(frame: .zero)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        // No side inset, so the body lines up exactly with the title above it.
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.textContainer?.lineFragmentPadding = 0
        textView.drawsBackground = false
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.delegate = context.coordinator

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = textView

        context.coordinator.textView = textView
        textView.textStorage?.delegate = context.coordinator
        context.coordinator.load(item)
        controller.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        guard let textView = coordinator.textView else { return }
        controller.textView = textView
        // Read the live item. `item` can be a moment old, and treating it as a change
        // from elsewhere would reload stale text over what was just typed.
        let current = model.item
        if current.richText != coordinator.lastData || (current.richText == nil && current.body != textView.string) {
            coordinator.load(current)
        } else if coordinator.styleKey != Coordinator.styleKey(for: current) {
            coordinator.restyle(current)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        private let model: ItemModel
        private let store: Store
        weak var textView: RichTextView?
        private(set) var lastData: Data?
        private(set) var styleKey = ""
        private var applyingStyle = false
        private var saveScheduled = false

        init(model: ItemModel, store: Store) {
            self.model = model
            self.store = store
        }

        static func styleKey(for item: Item) -> String {
            "\(item.fontFamily ?? "")|\(item.fontSize)|\(item.themeID)"
        }

        func load(_ item: Item) {
            guard let textView, let storage = textView.textStorage else { return }
            applyingStyle = true
            storage.setAttributedString(NoteFont.attributedBody(item))
            applyingStyle = false
            lastData = item.richText
            applyTextViewStyle(item)
        }

        func restyle(_ item: Item) {
            guard let textView, let storage = textView.textStorage else { return }
            applyingStyle = true
            NoteFont.restyle(storage, item: item)
            applyingStyle = false
            applyTextViewStyle(item)
        }

        private func applyTextViewStyle(_ item: Item) {
            guard let textView else { return }
            textView.typingAttributes = NoteFont.typingAttributes(item: item)
            textView.insertionPointColor = CardTheme.find(item.themeID).ink
            textView.fontMaker = { traits in NoteFont.body(item, traits: traits) }
            styleKey = Self.styleKey(for: item)
        }

        /// Watches the text itself, so typing, formatting, paste and undo all save the same way.
        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard !applyingStyle, !saveScheduled else { return }
            saveScheduled = true
            // The text system is mid-edit here, so read the result on the next turn.
            Task { @MainActor in
                self.saveScheduled = false
                self.save()
            }
        }

        private func save() {
            guard let storage = textView?.textStorage else { return }
            let data = try? storage.data(
                from: NSRange(location: 0, length: storage.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
            lastData = data
            let plain = storage.string
            store.update(model) { item in
                item.richText = data
                item.body = plain
            }
        }
    }
}

/// Draws finished text on a card. Ignores the mouse, so dragging over text moves the card.
struct RichTextDisplay: NSViewRepresentable {
    let text: NSAttributedString

    private static let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]

    static func height(of text: NSAttributedString, width: CGFloat) -> CGFloat {
        let size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        return text.boundingRect(with: size, options: options).height.rounded(.up)
    }

    final class DisplayView: NSView {
        var text = NSAttributedString() {
            didSet { needsDisplay = true }
        }

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func draw(_ dirtyRect: NSRect) {
            text.draw(with: bounds, options: RichTextDisplay.options)
        }
    }

    func makeNSView(context: Context) -> DisplayView {
        let view = DisplayView()
        view.text = text
        return view
    }

    func updateNSView(_ view: DisplayView, context: Context) {
        view.text = text
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    var active = false
    let ink: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(ink.opacity(active ? 1 : 0.65))
        .help(help)
    }
}

struct FormatBar: View {
    let controller: RichTextController
    let theme: CardTheme

    var body: some View {
        HStack(spacing: 0) {
            IconButton(symbol: "bold", help: "Bold", ink: theme.inkColor) {
                controller.textView?.noteToggleBold(nil)
            }
            IconButton(symbol: "italic", help: "Italic", ink: theme.inkColor) {
                controller.textView?.noteToggleItalic(nil)
            }
            IconButton(symbol: "underline", help: "Underline", ink: theme.inkColor) {
                controller.textView?.noteToggleUnderline(nil)
            }
            IconButton(symbol: "strikethrough", help: "Strikethrough", ink: theme.inkColor) {
                controller.textView?.noteToggleStrikethrough(nil)
            }
            IconButton(symbol: "highlighter", help: "Highlight", ink: theme.inkColor) {
                popUpMenu(highlightItems())
            }
        }
    }

    private func highlightItems() -> [NSMenuItem] {
        let ink = theme.ink
        var items: [NSMenuItem] = Highlight.all.map { highlight in
            actionItem(highlight.name, image: highlight.color.swatch()) {
                controller.textView?.applyHighlight(highlight.color, ink: ink)
            }
        }
        items.append(.separator())
        items.append(actionItem("Remove Highlight") {
            controller.textView?.applyHighlight(nil, ink: ink)
        })
        return items
    }
}
