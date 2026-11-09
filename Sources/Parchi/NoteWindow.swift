import AppKit
import ParchiCore
import SwiftUI

/// Where the pointer is on screen. Debug builds can override it, because synthetic
/// test events can't move the real pointer.
enum Pointer {
    #if DEBUG
    static var override: NSPoint?
    static var location: NSPoint { override ?? NSEvent.mouseLocation }
    #else
    static var location: NSPoint { NSEvent.mouseLocation }
    #endif
}

/// A note on the desktop. It never takes keyboard focus, so clicking it can't start
/// editing or pull focus from the app in front.
final class CardPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The popup editor. A borderless window can't take keyboard focus by default, and because
/// it never activates the app it can't rely on the main menu for standard editing shortcuts.
final class NotePanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Text fields here sit on the note's color, so the shared editor must not paint white.
    override func fieldEditor(_ createFlag: Bool, for object: Any?) -> NSText? {
        let editor = super.fieldEditor(createFlag, for: object)
        editor?.drawsBackground = false
        return editor
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            if event.keyCode == 53 {
                onEscape?()
                return
            }
            if handleCommandKey(event) { return }
        }
        super.sendEvent(event)
    }

    private func handleCommandKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command || flags == [.command, .shift] else { return false }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let shifted = flags.contains(.shift)

        if key == "z" {
            if shifted { firstResponder?.undoManager?.redo() } else { firstResponder?.undoManager?.undo() }
            return true
        }

        let action: Selector?
        switch (key, shifted) {
        case ("a", false): action = #selector(NSResponder.selectAll(_:))
        case ("c", false): action = #selector(NSText.copy(_:))
        case ("x", false): action = #selector(NSText.cut(_:))
        case ("v", false): action = #selector(NSText.paste(_:))
        case ("b", false): action = #selector(RichTextView.noteToggleBold(_:))
        case ("i", false): action = #selector(RichTextView.noteToggleItalic(_:))
        case ("u", false): action = #selector(RichTextView.noteToggleUnderline(_:))
        case ("x", true): action = #selector(RichTextView.noteToggleStrikethrough(_:))
        default: action = nil
        }
        guard let action else { return false }
        _ = firstResponder?.tryToPerform(action, with: self)
        return true
    }
}

/// View state of one desktop card, kept apart from the item so hovering isn't saved.
@Observable
final class WindowChrome {
    var hovering = false
    var scroll: CGFloat = 0
    var contentHeight: CGFloat = 0
    var maxScroll: CGFloat = 0 {
        didSet { scroll = min(scroll, maxScroll) }
    }

    func scrollBy(_ delta: CGFloat) {
        scroll = min(max(scroll - delta, 0), maxScroll)
    }
}

final class NoteHostingView<Content: View>: NSHostingView<Content> {
    var onHover: ((Bool) -> Void)?
    private var hoverArea: NSTrackingArea?

    // The first click on a card acts on what's under it, even while another app is in front.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        // activeAlways: cards must react to the pointer while another app is in front.
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover?(false)
    }
}

final class NoteWindowController: NSObject, NSWindowDelegate {
    let model: ItemModel
    let panel: CardPanel
    let chrome = WindowChrome()
    let edges = EdgeResizeView()

    private unowned let services: AppServices
    /// The last frame set by code. Only frames the user chose are saved, so a note moved
    /// because a monitor was unplugged returns home when the monitor comes back.
    private var programmaticFrame: NSRect?
    private var appliedKey: AppliedKey?

    private struct AppliedKey: Equatable {
        let pinned: Bool
        let allSpaces: Bool
        let opacity: Double
        let shadows: Bool
    }

    init(model: ItemModel, services: AppServices) {
        self.model = model
        self.services = services
        panel = CardPanel(
            contentRect: NSRect(x: 0, y: 0, width: 290, height: 170),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.delegate = self
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.animationBehavior = .none
        // Left unset, macOS decides from the window's pixels whether a click lands on it, and
        // it reads a card clipped to a custom shape as see-through, so clicks fall to the desktop.
        panel.ignoresMouseEvents = false

        let host = NoteHostingView(rootView: DesktopItemView(model: model, services: services, chrome: chrome))
        host.sizingOptions = []
        host.onHover = { [weak self] hovering in
            self?.chrome.hovering = hovering
        }

        // The edges sit above everything, so they win over dragging near the card's border.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 290, height: 170))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        edges.frame = container.bounds
        edges.autoresizingMask = [.width, .height]
        container.addSubview(host)
        container.addSubview(edges)
        panel.contentView = container

        edges.heightForWidth = { [unowned self] in self.photoHeight(forWidth: $0) }
        edges.widthForHeight = { [unowned self] in self.photoWidth(forHeight: $0) }

        apply()
        place()
    }

    static let desktopLevel = NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

    func apply() {
        let item = model.item
        let key = AppliedKey(
            pinned: item.pinned,
            allSpaces: item.allSpaces,
            opacity: item.opacity,
            shadows: services.settings.values.showShadows
        )
        guard key != appliedKey else { return }
        appliedKey = key

        panel.level = key.pinned ? .floating : Self.desktopLevel

        var behavior: NSWindow.CollectionBehavior = [.ignoresCycle]
        if key.pinned {
            behavior.insert(.managed)
            behavior.insert(.fullScreenAuxiliary)
        } else {
            behavior.insert(.stationary)
        }
        if key.allSpaces { behavior.insert(.canJoinAllSpaces) }
        panel.collectionBehavior = behavior

        panel.alphaValue = CGFloat(key.opacity)
        panel.hasShadow = key.shadows
        panel.invalidateShadow()
    }

    func place() {
        let home = model.item.frame?.rect ?? NSRect(x: 200, y: 200, width: 290, height: 170)
        let target = WindowPlacement.onScreen(fittedToPhoto(home), screens: NSScreen.screens.map(\.visibleFrame))
        programmaticFrame = target
        panel.setFrame(target, display: true)
    }

    func refitPhoto() {
        panel.setFrame(fittedToPhoto(panel.frame), display: true)
    }

    /// For photos, the same frame with the height that matches the picture. Top edge stays put.
    private func fittedToPhoto(_ frame: NSRect) -> NSRect {
        guard let height = photoHeight(forWidth: frame.width) else { return frame }
        return NSRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height)
    }

    private func photoHeight(forWidth width: CGFloat) -> CGFloat? {
        let item = model.item
        guard item.kind == .photo, let aspect = item.photoAspect else { return nil }
        return WindowPlacement.photoHeight(width: width, aspect: aspect, look: item.photoLook, hasCaption: item.hasCaption)
    }

    private func photoWidth(forHeight height: CGFloat) -> CGFloat? {
        let item = model.item
        guard item.kind == .photo, let aspect = item.photoAspect else { return nil }
        return WindowPlacement.photoWidth(height: height, aspect: aspect, look: item.photoLook, hasCaption: item.hasCaption)
    }

    func tearDown() {
        panel.delegate = nil
        retireWindow(panel)
    }

    private func saveFrame() {
        guard panel.frame != programmaticFrame else { return }
        programmaticFrame = nil
        let frame = ItemFrame(panel.frame)
        services.store.update(model, touch: false) { $0.frame = frame }
    }

    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidResize(_ notification: Notification) {
        saveFrame()
        // The shadow follows the paper's cut corners, so it has to be redrawn with them.
        Task { @MainActor [panel] in panel.invalidateShadow() }
    }
}

/// Hides a window now and destroys its content on the next turn of the event loop,
/// because this often runs from inside a button that lives in that same content.
func retireWindow(_ panel: NSPanel) {
    panel.orderOut(nil)
    Task { @MainActor in
        panel.contentView = nil
        panel.close()
    }
}

final class NoteWindowManager: NSObject {
    private var controllers: [String: NoteWindowController] = [:]
    private unowned let services: AppServices

    init(services: AppServices) {
        self.services = services
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func syncAll() {
        services.store.models.forEach { sync($0, old: nil) }
    }

    func sync(_ model: ItemModel, old: Item?) {
        let item = model.item
        guard item.state == .active, item.onDesktop else {
            remove(id: model.id)
            return
        }
        if let controller = controllers[model.id] {
            controller.apply()
            if let old, old.photoLook != item.photoLook || old.hasCaption != item.hasCaption {
                controller.refitPhoto()
            }
        } else {
            let controller = NoteWindowController(model: model, services: services)
            controllers[model.id] = controller
            controller.panel.orderFront(nil)
        }
    }

    func remove(id: String) {
        controllers.removeValue(forKey: id)?.tearDown()
    }

    func controller(for id: String) -> NoteWindowController? {
        controllers[id]
    }

    func reveal(_ model: ItemModel) {
        sync(model, old: nil)
        controllers[model.id]?.panel.orderFront(nil)
    }

    func refreshAppearance() {
        controllers.values.forEach { $0.apply() }
    }

    @objc private func screensChanged() {
        controllers.values.forEach { $0.place() }
    }
}

/// The whole surface of a card: dragging anywhere moves it, a plain click opens the editor.
struct CardInteraction: NSViewRepresentable {
    let onClick: () -> Void
    let onScroll: (CGFloat) -> Void

    final class SurfaceView: NSView {
        var onClick: (() -> Void)?
        var onScroll: ((CGFloat) -> Void)?
        private var startMouse = NSPoint.zero
        private var startOrigin = NSPoint.zero
        private var dragging = false

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            startMouse = Pointer.location
            startOrigin = window?.frame.origin ?? .zero
            dragging = false
        }

        override func mouseDragged(with event: NSEvent) {
            let mouse = Pointer.location
            let dx = mouse.x - startMouse.x
            let dy = mouse.y - startMouse.y
            // A few points of wobble during a click shouldn't count as a drag.
            if !dragging, hypot(dx, dy) < 3 { return }
            dragging = true
            window?.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
        }

        override func mouseUp(with event: NSEvent) {
            if !dragging { onClick?() }
        }

        override func scrollWheel(with event: NSEvent) {
            onScroll?(event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 10))
        }
    }

    func makeNSView(context: Context) -> SurfaceView {
        let view = SurfaceView()
        view.onClick = onClick
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: SurfaceView, context: Context) {
        view.onClick = onClick
        view.onScroll = onScroll
    }
}

/// A thin band around the card: the pointer changes near an edge or corner, and dragging
/// there resizes. Everywhere else the mouse passes through to the card.
final class EdgeResizeView: NSView {
    struct Edges: OptionSet {
        let rawValue: Int
        static let left = Edges(rawValue: 1)
        static let right = Edges(rawValue: 2)
        static let top = Edges(rawValue: 4)
        static let bottom = Edges(rawValue: 8)
    }

    /// For photos, these keep the picture's shape. They return nil for other items.
    var heightForWidth: ((CGFloat) -> CGFloat?)?
    var widthForHeight: ((CGFloat) -> CGFloat?)?

    private let band: CGFloat = 7
    private let cornerLength: CGFloat = 16
    private let minimum = NSSize(width: 170, height: 90)
    private var active: Edges = []
    private var startMouse = NSPoint.zero
    private var startFrame = NSRect.zero
    private var showingResizeCursor = false
    private var trackingArea: NSTrackingArea?

    func edges(at point: NSPoint) -> Edges {
        guard bounds.contains(point) else { return [] }
        let nearLeft = point.x <= band
        let nearRight = point.x >= bounds.width - band
        let nearBottom = point.y <= band
        let nearTop = point.y >= bounds.height - band
        let onSide = nearLeft || nearRight
        let onCap = nearTop || nearBottom

        var result: Edges = []
        if nearLeft || (onCap && point.x <= cornerLength) { result.insert(.left) }
        if nearRight || (onCap && point.x >= bounds.width - cornerLength) { result.insert(.right) }
        if nearBottom || (onSide && point.y <= cornerLength) { result.insert(.bottom) }
        if nearTop || (onSide && point.y >= bounds.height - cornerLength) { result.insert(.top) }
        return result
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        return edges(at: local).isEmpty ? nil : self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let found = edges(at: convert(event.locationInWindow, from: nil))
        if found.isEmpty {
            restoreCursor()
        } else {
            cursor(for: found).set()
            showingResizeCursor = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        restoreCursor()
    }

    private func restoreCursor() {
        guard showingResizeCursor else { return }
        showingResizeCursor = false
        NSCursor.arrow.set()
    }

    private func cursor(for edges: Edges) -> NSCursor {
        if #available(macOS 15.0, *) {
            let position: NSCursor.FrameResizePosition
            switch edges {
            case [.left, .top]: position = .topLeft
            case [.right, .top]: position = .topRight
            case [.left, .bottom]: position = .bottomLeft
            case [.right, .bottom]: position = .bottomRight
            case .left: position = .left
            case .right: position = .right
            case .top: position = .top
            default: position = .bottom
            }
            return NSCursor.frameResize(position: position, directions: .all)
        }
        if edges == .left || edges == .right { return .resizeLeftRight }
        if edges == .top || edges == .bottom { return .resizeUpDown }
        return .crosshair
    }

    override func mouseDown(with event: NSEvent) {
        active = edges(at: convert(event.locationInWindow, from: nil))
        startMouse = Pointer.location
        startFrame = window?.frame ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, !active.isEmpty else { return }
        let mouse = Pointer.location
        window.setFrame(resized(dx: mouse.x - startMouse.x, dy: mouse.y - startMouse.y), display: true)
    }

    override func mouseUp(with event: NSEvent) {
        active = []
    }

    private func resized(dx: CGFloat, dy: CGFloat) -> NSRect {
        var width = startFrame.width
        var height = startFrame.height
        if active.contains(.right) { width = max(minimum.width, startFrame.width + dx) }
        if active.contains(.left) { width = max(minimum.width, startFrame.width - dx) }
        if active.contains(.top) { height = max(minimum.height, startFrame.height + dy) }
        if active.contains(.bottom) { height = max(minimum.height, startFrame.height - dy) }

        if active.isDisjoint(with: [.left, .right]), let fitted = widthForHeight?(height) {
            width = max(minimum.width, fitted)
        }
        if let fitted = heightForWidth?(width) {
            height = fitted
        }

        // The edges opposite the ones being dragged stay where they are.
        let x = active.contains(.left) ? startFrame.maxX - width : startFrame.minX
        let y = active.contains(.top) ? startFrame.minY : startFrame.maxY - height
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

/// Cards belong to an app that usually isn't in front, and macOS only lets a background
/// app change the pointer through this private switch. Without it, resizing still works.
func allowCursorChangesInBackground() {
    typealias DefaultConnection = @convention(c) () -> Int32
    typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFBoolean) -> Int32
    let everyImage = UnsafeMutableRawPointer(bitPattern: -2)
    guard let connectionSymbol = dlsym(everyImage, "_CGSDefaultConnection"),
          let propertySymbol = dlsym(everyImage, "CGSSetConnectionProperty")
    else { return }
    let connection = unsafeBitCast(connectionSymbol, to: DefaultConnection.self)()
    let setProperty = unsafeBitCast(propertySymbol, to: SetProperty.self)
    _ = setProperty(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
}

/// Dragging here moves the window. Used by the popup, where the rest of the window edits.
struct DragRegion: NSViewRepresentable {
    final class DragView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}
}

private final class MenuBlockTarget: NSObject {
    private let block: () -> Void

    init(_ block: @escaping () -> Void) {
        self.block = block
    }

    @objc func run() { block() }
}

func actionItem(_ title: String, checked: Bool = false, image: NSImage? = nil, block: @escaping () -> Void) -> NSMenuItem {
    let target = MenuBlockTarget(block)
    let item = NSMenuItem(title: title, action: #selector(MenuBlockTarget.run), keyEquivalent: "")
    item.target = target
    // A menu item only holds its target weakly.
    item.representedObject = target
    item.state = checked ? .on : .off
    item.image = image
    return item
}

func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    let menu = NSMenu(title: title)
    items.forEach(menu.addItem)
    item.submenu = menu
    return item
}

func popUpMenu(_ items: [NSMenuItem]) {
    let menu = NSMenu()
    menu.autoenablesItems = false
    items.forEach(menu.addItem)
    menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
}
