#if DEBUG
import AppKit
import Carbon.HIToolbox
import ParchiCore
import SwiftUI

/// Debug builds only. Drives real windows from inside the app, because automating
/// them from outside needs Screen Recording and Accessibility permissions.
/// Run with PARCHI_SELFTEST=<output folder> and PARCHI_SELFTEST_PHASE=first|restart.
enum SelfTest {
    private static var lines: [String] = []
    private static var failures = 0

    private static var progress: URL?

    private static func expect(_ condition: Bool, _ name: String) {
        lines.append("\(condition ? "ok  " : "FAIL") \(name)")
        if !condition { failures += 1 }
        writeProgress()
    }

    private static func writeProgress() {
        guard let progress else { return }
        try? lines.joined(separator: "\n").appending("\n").write(to: progress, atomically: true, encoding: .utf8)
    }

    private static func note(_ text: String) {
        lines.append("info \(text)")
        writeProgress()
    }

    private static func settle(_ milliseconds: Int = 150) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }

    private static func textView(in view: NSView?) -> RichTextView? {
        guard let view else { return nil }
        if let found = view as? RichTextView { return found }
        for child in view.subviews {
            if let found = textView(in: child) { return found }
        }
        return nil
    }

    private static func press(_ panel: NSPanel, _ key: String, flags: NSEvent.ModifierFlags = .command, keyCode: UInt16 = 0) async {
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, characters: key,
            charactersIgnoringModifiers: key, isARepeat: false, keyCode: keyCode
        ) else { return }
        panel.sendEvent(event)
        await pumpEvents()
    }

    private static func mouse(_ panel: NSPanel, _ type: NSEvent.EventType, x: CGFloat, yFromTop: CGFloat) async {
        let point = NSPoint(x: x, y: panel.frame.height - yFromTop)
        guard let event = NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ) else { return }
        panel.sendEvent(event)
        await pumpEvents()
    }

    private static func click(_ panel: NSPanel, x: CGFloat, yFromTop: CGFloat) async {
        await mouse(panel, .leftMouseDown, x: x, yFromTop: yFromTop)
        await mouse(panel, .leftMouseUp, x: x, yFromTop: yFromTop)
        await settle(150)
    }

    /// Drags from a point on the panel, moving the (overridden) pointer by the given amount.
    private static func drag(_ panel: NSPanel, x: CGFloat, yFromTop: CGFloat, by delta: CGPoint) async {
        let start = NSPoint(x: 700, y: 500)
        Pointer.override = start
        await mouse(panel, .leftMouseDown, x: x, yFromTop: yFromTop)
        // Several steps, as a real mouse sends, in case one step disturbs the next.
        for step in 1...5 {
            let progress = CGFloat(step) / 5
            Pointer.override = NSPoint(x: start.x + delta.x * progress, y: start.y + delta.y * progress)
            await mouse(panel, .leftMouseDragged, x: x, yFromTop: yFromTop)
        }
        await mouse(panel, .leftMouseUp, x: x, yFromTop: yFromTop)
        Pointer.override = nil
        await settle(150)
    }

    /// Runs one real pass of the event loop. Undo groups close at the end of a pass,
    /// and synthetic input doesn't cause one by itself.
    private static func pumpEvents() async {
        if let event = NSEvent.otherEvent(
            with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0
        ) {
            NSApp.postEvent(event, atStart: false)
        }
        await settle(60)
    }

    private static let desktopLevel = NoteWindowController.desktopLevel

    private static var screenLocked: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return (session?["CGSSessionScreenIsLocked"] as? Int ?? 0) != 0
    }

    /// Renders a window's views directly, for when the compositor has nothing to capture.
    private static func renderOffscreen(_ window: NSWindow, _ name: String, in folder: URL) {
        guard let view = window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: folder.appendingPathComponent("\(name).png"))
    }

    /// Captures a window of this process through the system compositor.
    private static func snapshot(_ window: NSWindow, _ name: String, in folder: URL) {
        if screenLocked {
            renderOffscreen(window, name, in: folder)
            return
        }
        typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else {
            note("no capture function for \(name)")
            return
        }
        let capture = unsafeBitCast(symbol, to: Capture.self)
        // 8 = kCGWindowListOptionIncludingWindow, 1 = kCGWindowImageBoundsIgnoreFraming
        guard let image = capture(.null, 8, UInt32(window.windowNumber), 1)?.takeRetainedValue() else {
            note("capture returned nothing for \(name)")
            return
        }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: folder.appendingPathComponent("\(name).png"))
    }

    private static func makeSampleImage(width: Int, height: Int, at url: URL) throws {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGradient(starting: .systemTeal, ending: .systemOrange)?
            .draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 35)
        NSGraphicsContext.current = nil
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }

    private static func residentMegabytes() -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "rss=", "-p", "\(ProcessInfo.processInfo.processIdentifier)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        guard (try? process.run()) != nil else { return -1 }
        process.waitUntilExit()
        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) / 1024
    }

    static func run(services: AppServices, folder: URL, phase: String) async {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        progress = folder.appendingPathComponent("progress-\(phase).txt")
        // Test input goes straight to the panels. Whatever arrives through the app's event
        // queue is a person using the Mac, and it must not land in the test's popups.
        let realInput = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .leftMouseDown, .leftMouseUp]) { _ in nil }
        defer { realInput.map(NSEvent.removeMonitor) }
        await settle(400)
        do {
            if phase == "restart" {
                try await restartPhase(services: services, folder: folder)
            } else {
                try await firstPhase(services: services, folder: folder)
            }
        } catch {
            expect(false, "threw: \(error)")
        }
        lines.append("\(failures) failures")
        try? lines.joined(separator: "\n").appending("\n")
            .write(to: folder.appendingPathComponent("result-\(phase).txt"), atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }

    /// The copy and paste checks use the real clipboard, so whatever was on it goes back after.
    private static func savePasteboard() -> [[NSPasteboard.PasteboardType: Data]] {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            var copy: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { copy[type] = data }
            }
            return copy
        }
    }

    private static func restorePasteboard(_ saved: [[NSPasteboard.PasteboardType: Data]]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(saved.map { contents in
            let item = NSPasteboardItem()
            for (type, data) in contents { item.setData(data, forType: type) }
            return item
        })
    }

    private static func firstPhase(services: AppServices, folder: URL) async throws {
        let savedPasteboard = savePasteboard()
        defer { restorePasteboard(savedPasteboard) }
        let store = services.store
        let windows = services.windows

        // MARK: Text note, typing and autosave
        services.newNote()
        await settle(300)
        let noteModel = try require(store.models.first, "note created")
        let noteController = try require(windows.controller(for: noteModel.id), "note window exists")
        let card = noteController.panel
        expect(card.isVisible, "note card visible")
        expect(card.level == desktopLevel, "card stays on the desktop while its note is edited")
        expect(!card.canBecomeKey, "card can't take keyboard focus")
        expect(textView(in: card.contentView) == nil, "card has no text editor in it")

        let panel = try require(services.editor.panel, "new note opens the popup editor")
        if screenLocked {
            note("focus check skipped: macOS gives no window focus while the screen is locked")
        } else {
            expect(panel.isKeyWindow, "popup takes keyboard focus")
        }
        expect(panel.level == .floating, "popup sits above other windows")
        expect(!panel.frame.intersects(card.frame), "popup opens beside the card")

        let editor = try require(textView(in: panel.contentView), "popup has a text view")
        expect(panel.firstResponder === editor, "cursor is in the new note's body")
        editor.insertText("Hello bold world", replacementRange: editor.selectedRange())
        await pumpEvents()
        expect(noteModel.item.body == "Hello bold world", "typing updates the note")
        await settle(500)
        let saved = try NoteDatabase(path: store.paths.database.path).allItems().first { $0.id == noteModel.id }
        expect(saved?.body == "Hello bold world", "typing reaches the database without any save action")

        // MARK: Formatting through real key events
        let storage = try require(editor.textStorage, "text storage")
        editor.setSelectedRange(NSRange(location: 6, length: 4))
        await press(panel, "b")
        let boldFont = storage.attribute(.font, at: 6, effectiveRange: nil) as? NSFont
        expect(boldFont.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } == true, "⌘B bolds the selection")
        let plainFont = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        expect(plainFont.map { !NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } == true, "⌘B leaves other text alone")

        await press(panel, "z")
        let undone = storage.attribute(.font, at: 6, effectiveRange: nil) as? NSFont
        expect(undone.map { !NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } == true, "⌘Z undoes formatting")
        await press(panel, "z", flags: [.command, .shift])
        let redone = storage.attribute(.font, at: 6, effectiveRange: nil) as? NSFont
        expect(redone.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } == true, "⇧⌘Z redoes formatting")

        editor.setSelectedRange(NSRange(location: 0, length: 5))
        await press(panel, "i")
        await press(panel, "u")
        await press(panel, "x", flags: [.command, .shift])
        let attributes = storage.attributes(at: 0, effectiveRange: nil)
        expect(attributes[.underlineStyle] != nil, "⌘U underlines")
        expect(attributes[.strikethroughStyle] != nil, "⇧⌘X strikes through")
        expect((attributes[.font] as? NSFont).map { NSFontManager.shared.traits(of: $0).contains(.italicFontMask) } == true, "⌘I italicizes")

        editor.setSelectedRange(NSRange(location: 11, length: 5))
        editor.applyHighlight(Highlight.all[0].color, ink: CardTheme.find("kagaz").ink)
        await pumpEvents()
        expect(storage.attribute(.backgroundColor, at: 12, effectiveRange: nil) != nil, "highlight applies")

        await press(panel, "a")
        expect(editor.selectedRange().length == storage.length, "⌘A selects all")
        await press(panel, "c")
        expect(NSPasteboard.general.string(forType: .string) == "Hello bold world", "⌘C copies")
        editor.setSelectedRange(NSRange(location: storage.length, length: 0))
        await press(panel, "v")
        expect(editor.string == "Hello bold worldHello bold world", "⌘V pastes")
        await press(panel, "z")
        expect(editor.string == "Hello bold world", "⌘Z undoes paste")
        await settle()
        expect(noteModel.item.body == "Hello bold world", "undo reaches the saved note")

        await settle()
        let rtf = try require(noteModel.item.richText, "rich text stored")
        let parsed = try NSMutableAttributedString(
            data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil
        )
        if parsed.string != "Hello bold world" {
            note("saved rich text was: \(parsed.string.debugDescription), body: \(noteModel.item.body.debugDescription), editor: \(editor.string.debugDescription)")
        }
        expect(parsed.string == "Hello bold world", "rich text round-trips without extra characters")
        NoteFont.restyle(parsed, item: noteModel.item)
        expect((parsed.attribute(.font, at: 6, effectiveRange: nil) as? NSFont).map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } == true, "bold survives saving")
        expect(parsed.attribute(.backgroundColor, at: 12, effectiveRange: nil) != nil, "highlight survives saving")
        expect(parsed.attribute(.underlineStyle, at: 0, effectiveRange: nil) != nil, "underline survives saving")

        // MARK: Fast typing must not be overwritten by a delayed view update
        let fast = store.createNote(title: "Fast")
        services.editor.open(fast)
        await settle(300)
        let fastEditor = try require(textView(in: services.editor.panel?.contentView), "fast note editor")
        let fastText = String(repeating: "abcdefghij", count: 40)
        for character in fastText {
            fastEditor.insertText(String(character), replacementRange: fastEditor.selectedRange())
            await Task.yield()
            if Int.random(in: 0..<4) == 0 { try? await Task.sleep(for: .milliseconds(3)) }
        }
        await settle(400)
        expect(fastEditor.string == fastText, "fast typing keeps every character on screen")
        expect(fast.item.body == fastText, "fast typing keeps every character in the note")
        store.deletePermanently([fast])
        await settle()
        expect(services.editor.panel == nil, "deleting a note closes its popup")

        // MARK: Window behavior
        services.editor.open(noteModel)
        await settle(200)
        let openPopup = try require(services.editor.panel, "popup reopens")
        await press(openPopup, "\u{1B}", flags: [], keyCode: 53)
        await settle()
        expect(services.editor.panel == nil, "Esc closes the popup")

        let other = store.createNote(title: "Other", text: "Takes focus away")
        windows.reveal(other)
        await settle()

        store.update(noteModel, touch: false) { $0.pinned = true }
        expect(card.level == .floating, "pin keeps note above windows")
        expect(card.collectionBehavior.contains(.fullScreenAuxiliary), "pinned note can sit over full-screen apps")
        store.update(noteModel, touch: false) { $0.pinned = false }
        expect(card.level == desktopLevel, "unpin returns to desktop level")
        expect(card.collectionBehavior.contains(.stationary), "desktop note stays put in Mission Control")

        expect(card.collectionBehavior.contains(.canJoinAllSpaces), "all Spaces is the default")
        store.update(noteModel, touch: false) { $0.allSpaces = false }
        expect(!card.collectionBehavior.contains(.canJoinAllSpaces), "current Space only")
        store.update(noteModel, touch: false) { $0.allSpaces = true }

        store.update(noteModel, touch: false) { $0.opacity = 0.6 }
        expect(abs(card.alphaValue - 0.6) < 0.01, "opacity applies")
        store.update(noteModel, touch: false) { $0.opacity = 1 }

        services.settings.values.showShadows = false
        expect(!card.hasShadow, "shadow setting applies")
        services.settings.values.showShadows = true
        expect(card.hasShadow, "shadow setting restores")

        store.update(noteModel, touch: false) { $0.onDesktop = false }
        expect(windows.controller(for: noteModel.id) == nil, "hide removes window")
        store.update(noteModel, touch: false) { $0.onDesktop = true }
        await settle()
        let shownAgain = try require(windows.controller(for: noteModel.id), "show brings window back")
        expect(shownAgain.panel.isVisible, "shown window is visible")

        // MARK: Monitor unplug
        let home = CGRect(x: 9000, y: 300, width: 240, height: 220)
        store.update(noteModel, touch: false) { $0.frame = ItemFrame(home) }
        shownAgain.place()
        await settle()
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.contains(shownAgain.panel.frame) }
        expect(onScreen, "note from a missing monitor is pulled on-screen")
        expect(noteModel.item.frame?.rect == home, "its home position is remembered for when the monitor returns")
        store.update(noteModel, touch: false) { $0.frame = ItemFrame(CGRect(x: 300, y: 300, width: 260, height: 230)) }
        shownAgain.place()
        await settle()
        expect(shownAgain.panel.frame.origin == CGPoint(x: 300, y: 300), "note returns home")

        // MARK: Dragging and clicking the card
        let dragStart = shownAgain.panel.frame.origin
        await drag(shownAgain.panel, x: 150, yFromTop: 25, by: CGPoint(x: 40, y: -30))
        expect(shownAgain.panel.frame.origin == CGPoint(x: dragStart.x + 40, y: dragStart.y - 30), "note moves when dragged by its title")
        expect(noteModel.item.frame?.x == dragStart.x + 40, "dragging saves the new position")
        expect(services.editor.panel == nil, "dragging doesn't open the editor")

        let bodyDragStart = shownAgain.panel.frame.origin
        await drag(shownAgain.panel, x: 150, yFromTop: 200, by: CGPoint(x: -20, y: 15))
        expect(shownAgain.panel.frame.origin == CGPoint(x: bodyDragStart.x - 20, y: bodyDragStart.y + 15), "note moves when dragged by empty space")

        await click(shownAgain.panel, x: 150, yFromTop: 60)
        expect(services.editor.model?.id == noteModel.id, "clicking a note opens its popup")
        expect(textView(in: shownAgain.panel.contentView) == nil, "clicking doesn't start editing on the card")
        services.editor.close()
        await settle()

        shownAgain.chrome.hovering = true
        await settle(250)
        let gripFrame = shownAgain.panel.frame
        await drag(shownAgain.panel, x: gripFrame.width - 4, yFromTop: gripFrame.height - 4, by: CGPoint(x: 30, y: -20))
        let resized = shownAgain.panel.frame
        expect(resized.width == gripFrame.width + 30 && resized.height == gripFrame.height + 20, "corner resizes the card")
        expect(resized.maxY == gripFrame.maxY && resized.minX == gripFrame.minX, "resizing keeps the top left corner")
        expect(services.editor.panel == nil, "resizing doesn't open the editor")

        let edgePanel = shownAgain.panel
        let edgeView = shownAgain.edges
        expect(edgeView.edges(at: NSPoint(x: 3, y: 80)) == .left, "left side is a resize zone")
        expect(edgeView.edges(at: NSPoint(x: edgeView.bounds.width - 3, y: 80)) == .right, "right side is a resize zone")
        expect(edgeView.edges(at: NSPoint(x: 120, y: edgeView.bounds.height - 3)) == .top, "top side is a resize zone")
        expect(edgeView.edges(at: NSPoint(x: 120, y: 3)) == .bottom, "bottom side is a resize zone")
        expect(edgeView.edges(at: NSPoint(x: 3, y: 3)) == [.left, .bottom], "corner resizes both ways")
        expect(edgeView.edges(at: NSPoint(x: 120, y: 80)).isEmpty, "the middle is not a resize zone")

        let beforeRight = edgePanel.frame
        await drag(edgePanel, x: beforeRight.width - 3, yFromTop: beforeRight.height / 2, by: CGPoint(x: 25, y: 40))
        let afterRight = edgePanel.frame
        let rightWidthGrew = afterRight.width == beforeRight.width + 25
        expect(rightWidthGrew && afterRight.height == beforeRight.height && afterRight.origin == beforeRight.origin, "right edge changes only the width")

        let beforeLeft = edgePanel.frame
        await drag(edgePanel, x: 3, yFromTop: beforeLeft.height / 2, by: CGPoint(x: -15, y: 0))
        let afterLeft = edgePanel.frame
        expect(afterLeft.width == beforeLeft.width + 15 && afterLeft.maxX == beforeLeft.maxX, "left edge grows leftward")

        let beforeTop = edgePanel.frame
        await drag(edgePanel, x: beforeTop.width / 2, yFromTop: 3, by: CGPoint(x: 0, y: 18))
        let afterTop = edgePanel.frame
        expect(afterTop.height == beforeTop.height + 18 && afterTop.minY == beforeTop.minY, "top edge grows upward")

        let beforeBottom = edgePanel.frame
        await drag(edgePanel, x: beforeBottom.width / 2, yFromTop: beforeBottom.height - 3, by: CGPoint(x: 0, y: -12))
        let afterBottom = edgePanel.frame
        expect(afterBottom.height == beforeBottom.height + 12 && afterBottom.maxY == beforeBottom.maxY, "bottom edge grows downward")
        expect(services.editor.panel == nil, "edge drags don't open the editor")

        let beforeFloor = edgePanel.frame
        await drag(edgePanel, x: beforeFloor.width - 3, yFromTop: beforeFloor.height / 2, by: CGPoint(x: -5000, y: 0))
        expect(edgePanel.frame.width == 170, "cards can't shrink below the minimum width")
        shownAgain.chrome.hovering = false
        await settle()

        // MARK: User-style move is saved
        shownAgain.panel.setFrameOrigin(NSPoint(x: 420, y: 360))
        await settle()
        expect(noteModel.item.frame?.x == 420 && noteModel.item.frame?.y == 360, "moving a note saves its position")

        // MARK: To-do list
        let todo = store.createTodo(title: "Launch", items: ["Write code", "Test it", "Ship it"])
        await settle()
        expect(windows.controller(for: todo.id)?.panel.isVisible == true, "to-do window visible")
        store.update(todo) { $0.tasks[0].done = true }
        let order = TodoOrdering.display(todo.item.tasks, completedLast: true).map(\.text)
        expect(order == ["Test it", "Ship it", "Write code"], "completed to-do moves to bottom")
        let todoPanel = try require(windows.controller(for: todo.id), "to-do controller").panel
        expect(services.editor.panel == nil, "creating a to-do with items opens no popup")
        let todoOrigin = todoPanel.frame.origin
        await drag(todoPanel, x: 120, yFromTop: 66, by: CGPoint(x: -40, y: -30))
        expect(todoPanel.frame.origin == CGPoint(x: todoOrigin.x - 40, y: todoOrigin.y - 30), "to-do card moves when dragged by a task's text")
        expect(services.editor.panel == nil, "dragging a to-do card doesn't open the editor")
        let todoEmptyOrigin = todoPanel.frame.origin
        await drag(todoPanel, x: 200, yFromTop: 190, by: CGPoint(x: 25, y: 25))
        expect(todoPanel.frame.origin == CGPoint(x: todoEmptyOrigin.x + 25, y: todoEmptyOrigin.y + 25), "to-do card moves when dragged by empty space")

        // MARK: Real clicks, on a card that can't take focus
        let clickTarget = store.createTodo(title: "Clicks", items: ["One", "Two"])
        await settle(400)
        let clickController = try require(windows.controller(for: clickTarget.id), "click target window")
        let clickPanel = clickController.panel
        clickController.chrome.hovering = true
        await settle(250)
        let pinX = clickPanel.frame.width / 2 - 28
        let controlsY = clickPanel.frame.height - 28
        await click(clickPanel, x: pinX, yFromTop: controlsY)
        expect(clickTarget.item.pinned, "first click on the pin button works")
        expect(services.editor.panel == nil, "clicking a hover button doesn't open the editor")
        await click(clickPanel, x: pinX, yFromTop: controlsY)
        expect(!clickTarget.item.pinned, "second click unpins")
        await click(clickPanel, x: 32, yFromTop: 66)
        expect(clickTarget.item.tasks.first?.done == true, "clicking a checkbox on the card completes the task")
        expect(services.editor.panel == nil, "clicking a checkbox doesn't open the editor")
        await click(clickPanel, x: 150, yFromTop: 66)
        expect(services.editor.model?.id == clickTarget.id, "clicking a to-do card opens its popup")
        services.editor.close()
        await settle()

        let longNote = store.createNote(title: "Long", text: (1...60).map { "Line \($0)" }.joined(separator: "\n"))
        await settle(400)
        let longController = try require(windows.controller(for: longNote.id), "long note window")
        expect(longController.chrome.maxScroll > 0, "long note can scroll on its card")
        longController.chrome.scrollBy(-40)
        await settle()
        expect(longController.chrome.scroll == 40, "scrolling moves the card's text")
        longController.chrome.scrollBy(-1_000_000)
        expect(longController.chrome.scroll == longController.chrome.maxScroll, "scrolling stops at the end")
        store.deletePermanently([longNote])

        let trashTarget = store.createNote(title: "Trash me", text: "x")
        await settle(300)
        let trashController = try require(windows.controller(for: trashTarget.id), "trash target window")
        trashController.chrome.hovering = true
        await settle(250)
        await click(trashController.panel, x: trashController.panel.frame.width / 2 + 56, yFromTop: trashController.panel.frame.height - 28)
        expect(trashTarget.item.state == .trashed, "trash button on the card works")
        expect(windows.controller(for: trashTarget.id) == nil, "trashed card disappears")
        store.deletePermanently([trashTarget])

        // MARK: Typing in a to-do list
        services.newTodo()
        await settle(500)
        let typed = try require(store.models.first, "typed list created")
        let typedPanel = try require(services.editor.panel, "new to-do list opens the popup")
        let fieldEditor = typedPanel.firstResponder as? NSTextView
        expect(fieldEditor != nil, "new to-do list puts the cursor in its first task")
        fieldEditor?.insertText("Buy milk", replacementRange: NSRange(location: 0, length: 0))
        await pumpEvents()
        expect(typed.item.tasks.first?.text == "Buy milk", "typing in a to-do updates it")
        fieldEditor?.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        await settle(400)
        expect(typed.item.tasks.count == 2, "Return adds the next to-do")
        expect(typed.item.tasks.first?.text == "Buy milk", "Return leaves the task text clean")
        let nextEditor = typedPanel.firstResponder as? NSTextView
        expect(nextEditor?.string == "", "cursor moves to the new to-do")
        services.editor.close()
        await settle()

        // MARK: Global shortcuts
        expect(services.hotKeys.failed.isEmpty, "global shortcuts registered with the system")
        let countBefore = store.models.count
        var hotKeyEvent: EventRef?
        CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, EventAttributes(kEventAttributeNone), &hotKeyEvent)
        var identifier = EventHotKeyID(signature: 0x5052_4348, id: HotKeyAction.newNote.hotKeyID)
        SetEventParameter(hotKeyEvent, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &identifier)
        SendEventToEventTarget(hotKeyEvent, GetApplicationEventTarget())
        await settle(300)
        expect(store.models.count == countBefore + 1, "shortcut event creates a note")
        expect(services.editor.panel != nil, "shortcut opens the popup")
        services.editor.close()
        await settle()

        // MARK: Photos
        let original = folder.appendingPathComponent("sample.png")
        try makeSampleImage(width: 1200, height: 800, at: original)
        let photo = try store.addPhoto(from: original)
        await settle(300)
        expect(photo.item.photoAspect == 1.5, "photo aspect read")
        let photoFile = store.paths.photos.appendingPathComponent(try require(photo.item.photoFile, "photo file name"))
        expect(FileManager.default.fileExists(atPath: photoFile.path), "photo copied into library")
        let photoController = try require(windows.controller(for: photo.id), "photo window exists")
        let frameBefore = photoController.panel.frame
        store.update(photo, touch: false) { $0.photoLook = .bare }
        await settle()
        let expected = WindowPlacement.photoHeight(width: frameBefore.width, aspect: 1.5, look: .bare)
        expect(photoController.panel.frame.height == expected, "window refits when the photo look changes")
        expect(photoController.panel.frame.maxY == frameBefore.maxY, "photo keeps its top edge")
        snapshot(photoController.panel, "photo-noframe", in: folder)
        store.update(photo, touch: false) { $0.photoLook = .stamp }
        await settle()
        let borderFrame = photoController.panel.frame
        await drag(photoController.panel, x: borderFrame.width - 3, yFromTop: borderFrame.height / 2, by: CGPoint(x: 40, y: 0))
        let borderExpected = WindowPlacement.photoHeight(width: borderFrame.width + 40, aspect: 1.5, look: .stamp)
        expect(photoController.panel.frame.height == borderExpected, "photo keeps its shape when resized from a side")
        let tallFrame = photoController.panel.frame
        await drag(photoController.panel, x: tallFrame.width / 2, yFromTop: 3, by: CGPoint(x: 0, y: 30))
        let tallAfter = photoController.panel.frame
        let tallRatio = WindowPlacement.photoHeight(width: tallAfter.width, aspect: 1.5, look: .stamp)
        expect(tallAfter.height == tallRatio && tallAfter.width > tallFrame.width, "photo keeps its shape when resized from the top")
        let heightBeforeCaption = photoController.panel.frame.height
        store.update(photo, touch: false) { $0.title = "Caption" }
        await settle()
        expect(photoController.panel.frame.height != heightBeforeCaption, "adding a caption makes room for it")
        store.update(photo, touch: false) { $0.title = "" }
        await settle()

        // MARK: Archive and Trash
        let doomed = store.createNote(title: "Doomed", text: "bye")
        await settle()
        store.setState(doomed, .archived)
        expect(windows.controller(for: doomed.id) == nil, "archive removes window")
        expect(store.items(in: .archive, search: "", themeID: nil).contains { $0.id == doomed.id }, "item is in Archive")
        store.setState(doomed, .active)
        expect(windows.controller(for: doomed.id) != nil, "unarchive restores window")
        store.setState(doomed, .trashed)
        expect(windows.controller(for: doomed.id) == nil, "trash removes window")
        expect(doomed.item.trashedAt != nil, "trash date recorded")
        store.purgeExpiredTrash()
        expect(store.model(id: doomed.id) != nil, "fresh trash is kept")
        store.update(doomed, touch: false) { $0.trashedAt = Date().addingTimeInterval(-8 * 86400) }
        store.purgeExpiredTrash()
        expect(store.model(id: doomed.id) == nil, "trash older than 7 days is deleted")

        let trashedPhoto = try store.addPhoto(from: original)
        let trashedFile = store.paths.photos.appendingPathComponent(try require(trashedPhoto.item.photoFile, "file"))
        store.deletePermanently([trashedPhoto])
        expect(!FileManager.default.fileExists(atPath: trashedFile.path), "deleting a photo removes its file")

        // MARK: Search and filter
        expect(store.items(in: .todos, search: "ship", themeID: nil).map(\.id) == [todo.id], "search finds task text")
        expect(store.items(in: .notes, search: "bold wor", themeID: nil).map(\.id) == [noteModel.id], "search finds partial words")
        expect(store.items(in: .notes, search: "nothing-matches", themeID: nil).isEmpty, "search excludes non-matches")
        store.update(other, touch: false) { $0.themeID = "neem" }
        expect(store.items(in: .notes, search: "", themeID: "neem").map(\.id) == [other.id], "theme filter")

        // MARK: Screenshots
        let sampled = store.createNote(title: "Late night idea", text: "Sticky notes, but they feel like paper.")
        store.update(sampled, touch: false) { $0.themeID = "raat" }
        var themed: [(ItemModel, String)] = []
        for theme in CardTheme.all {
            let isTodo = ["haldi", "neem", "rasid"].contains(theme.id)
            let sample = isTodo
                ? store.createTodo(title: "Today", items: ["Write the quarterly report", "Call the bank"])
                : store.createNote(title: "Ideas", text: "A sample note with enough text to wrap onto a second line.")
            store.update(sample, touch: false) { $0.themeID = theme.id }
            themed.append((sample, "theme-\(theme.id)"))
        }
        var looks: [(ItemModel, String)] = []
        for look in PhotoLook.allCases {
            let sample = try store.addPhoto(from: original)
            store.update(sample, touch: false) { item in
                item.photoLook = look
                item.title = look.showsCaption ? "Goa, last winter" : ""
            }
            looks.append((sample, "look-\(look.rawValue)"))
        }
        await settle(300)
        for (model, name) in themed + looks + [(todo, "todo")] {
            if let controller = windows.controller(for: model.id) {
                snapshot(controller.panel, name, in: folder)
                controller.chrome.hovering = true
                await settle(250)
                snapshot(controller.panel, "\(name)-hover", in: folder)
                controller.chrome.hovering = false
            }
        }

        for (model, name) in [(noteModel, "popup-note"), (todo, "popup-todo"), (photo, "popup-photo"), (sampled, "popup-dark")] {
            services.editor.open(model)
            await settle(450)
            if let popup = services.editor.panel { snapshot(popup, name, in: folder) }
            services.editor.close()
            await settle()
        }

        services.openMain(selecting: noteModel)
        await settle(900)
        if let window = NSApp.windows.first(where: { $0.title == "Parchi" }) {
            snapshot(window, "main-notes", in: folder)
            services.openMain(selecting: todo)
            await settle(500)
            snapshot(window, "main-todo", in: folder)
            services.openMain(selecting: photo)
            await settle(500)
            snapshot(window, "main-photo", in: folder)
        } else {
            expect(false, "main window exists")
        }
        services.openSettings()
        await settle(600)
        if let window = NSApp.windows.first(where: { $0.title == "Parchi Settings" }) {
            snapshot(window, "settings", in: folder)
        } else {
            expect(false, "settings window exists")
        }

        // MARK: Scale
        let before = residentMegabytes()
        let clock = ContinuousClock()
        var created: [ItemModel] = []
        let elapsed = clock.measure {
            for index in 0..<250 {
                created.append(store.createNote(title: "Note \(index)", text: "Body of note \(index)"))
            }
        }
        await settle(800)
        note("created 250 note windows in \(elapsed)")
        expect(created.allSatisfy { windows.controller(for: $0.id)?.panel.isVisible == true }, "250 extra notes all have visible windows")
        note("memory \(before) MB before, \(residentMegabytes()) MB after 250 extra windows")
        let flushTime = clock.measure { try? store.flush() }
        note("flush took \(flushTime)")
        let searchTime = clock.measure { _ = store.items(in: .notes, search: "note 249", themeID: nil) }
        note("search over all notes took \(searchTime)")
        expect(store.items(in: .notes, search: "Note 249", themeID: nil).count == 1, "search works at scale")
        store.deletePermanently(created)
        await settle(300)
        expect(created.allSatisfy { windows.controller(for: $0.id) == nil }, "deleted notes lose their windows")

        // MARK: Hand over to the restart phase
        try store.flush()
        let expectedState = [
            "note": noteModel.id,
            "todo": todo.id,
            "photo": photo.id,
            "count": "\(store.models.count)",
        ]
        let data = try JSONEncoder().encode(expectedState)
        try data.write(to: folder.appendingPathComponent("restart.json"))
    }

    private static func restartPhase(services: AppServices, folder: URL) async throws {
        let store = services.store
        let windows = services.windows
        let data = try Data(contentsOf: folder.appendingPathComponent("restart.json"))
        let expected = try JSONDecoder().decode([String: String].self, from: data)

        expect("\(store.models.count)" == expected["count"], "every item came back after restart")
        let noteModel = try require(store.model(id: expected["note"]), "note exists after restart")
        let controller = try require(windows.controller(for: noteModel.id), "note window reopened")
        expect(controller.panel.isVisible, "note visible after restart")
        expect(controller.panel.frame.origin == CGPoint(x: 420, y: 360), "note reopened where it was left")

        expect(textView(in: controller.panel.contentView) == nil, "card has no editor after restart")
        services.editor.open(noteModel)
        await settle(300)
        let editor = try require(textView(in: services.editor.panel?.contentView), "editor exists")
        expect(editor.string == "Hello bold world", "text survived restart")
        let storage = try require(editor.textStorage, "storage")
        expect((storage.attribute(.font, at: 6, effectiveRange: nil) as? NSFont).map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } == true, "bold survived restart")
        expect(storage.attribute(.backgroundColor, at: 12, effectiveRange: nil) != nil, "highlight survived restart")

        let todo = try require(store.model(id: expected["todo"]), "to-do exists after restart")
        expect(todo.item.tasks.map(\.done) == [true, false, false], "to-do state survived restart")
        expect(windows.controller(for: todo.id) != nil, "to-do window reopened")

        let photo = try require(store.model(id: expected["photo"]), "photo exists after restart")
        expect(windows.controller(for: photo.id) != nil, "photo window reopened")
        expect(PhotoLibrary.image(file: photo.item.photoFile, folder: store.paths.photos, maxPixel: 400) != nil, "photo file loads after restart")
    }

    private struct Missing: Error, CustomStringConvertible {
        let description: String
    }

    private static func require<T>(_ value: T?, _ name: String) throws -> T {
        guard let value else {
            lines.append("FAIL \(name)")
            failures += 1
            throw Missing(description: name)
        }
        return value
    }
}
#endif
