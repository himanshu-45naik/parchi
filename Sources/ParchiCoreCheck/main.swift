// Standalone checks for ParchiCore. A plain executable because Swift's test
// frameworks are not usable with Command Line Tools alone.
import CoreGraphics
import Foundation
import ParchiCore

nonisolated(unsafe) var failures = 0
nonisolated(unsafe) var checks = 0

func expect(_ condition: @autoclosure () throws -> Bool, line: Int = #line) {
    checks += 1
    do {
        if try !condition() {
            failures += 1
            print("  FAILED at line \(line)")
        }
    } catch {
        failures += 1
        print("  THREW at line \(line): \(error)")
    }
}

func check(_ name: String, _ body: () throws -> Void) {
    print("- \(name)")
    do {
        try body()
    } catch {
        failures += 1
        print("  THREW: \(error)")
    }
}

check("database round-trips every field") {
    let db = try NoteDatabase()
    var item = Item(kind: .todo)
    item.title = "Groceries"
    item.tasks = [TodoTask(text: "Milk", done: true), TodoTask(text: "Eggs")]
    item.richText = Data([1, 2, 3])
    item.frame = ItemFrame(CGRect(x: 10, y: 20, width: 240, height: 200))
    item.pinned = true
    try db.save([item])

    let loaded = try db.allItems()[0]
    expect(loaded.title == "Groceries")
    expect(loaded.tasks == item.tasks)
    expect(loaded.richText == item.richText)
    expect(loaded.frame == item.frame)
    expect(loaded.pinned)
    expect(loaded.kind == .todo)
}

check("no limit on item count") {
    let db = try NoteDatabase()
    let items = (0..<5000).map { index -> Item in
        var item = Item(kind: index % 2 == 0 ? .note : .todo)
        item.title = "Item \(index)"
        return item
    }
    try db.save(items)
    expect(try db.allItems().count == 5000)
}

check("database reopens from disk with data intact") {
    let path = NSTemporaryDirectory() + UUID().uuidString + ".sqlite"
    defer { try? FileManager.default.removeItem(atPath: path) }
    var item = Item(kind: .note)
    item.body = "survives restart"
    try NoteDatabase(path: path).save([item])
    expect(try NoteDatabase(path: path).allItems().map(\.body) == ["survives restart"])
}

check("save updates existing row, delete removes it") {
    let db = try NoteDatabase()
    var item = Item(kind: .note)
    try db.save([item])
    item.body = "changed"
    try db.save([item])
    expect(try db.allItems().map(\.body) == ["changed"])
    try db.delete(ids: [item.id])
    expect(try db.allItems().isEmpty)
}

check("trash expires after seven days only") {
    let now = Date()
    var old = Item(kind: .note)
    old.state = .trashed
    old.trashedAt = now.addingTimeInterval(-8 * 86400)
    var recent = Item(kind: .note)
    recent.state = .trashed
    recent.trashedAt = now.addingTimeInterval(-6 * 86400)
    var active = Item(kind: .note)
    active.trashedAt = now.addingTimeInterval(-30 * 86400)
    expect(Retention.expired([old, recent, active], now: now).map(\.id) == [old.id])
}

check("completed tasks move to bottom, keep order") {
    let a = TodoTask(text: "a", done: true)
    let b = TodoTask(text: "b")
    let c = TodoTask(text: "c", done: true)
    let d = TodoTask(text: "d")
    expect(TodoOrdering.display([a, b, c, d], completedLast: true) == [b, d, a, c])
    expect(TodoOrdering.display([a, b, c, d], completedLast: false) == [a, b, c, d])
}

check("window placement") {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let fine = CGRect(x: 100, y: 100, width: 240, height: 200)
    expect(WindowPlacement.onScreen(fine, screens: [screen]) == fine)

    let lost = CGRect(x: 3000, y: 300, width: 240, height: 200)
    let placed = WindowPlacement.onScreen(lost, screens: [screen])
    expect(screen.contains(placed))
    expect(placed.size == lost.size)

    let tooHigh = CGRect(x: 100, y: 800, width: 240, height: 200)
    expect(WindowPlacement.onScreen(tooHigh, screens: [screen]).maxY <= screen.maxY)

    let small = CGRect(x: 0, y: 0, width: 800, height: 600)
    let huge = CGRect(x: 5000, y: 5000, width: 2000, height: 2000)
    expect(small.contains(WindowPlacement.onScreen(huge, screens: [small])))

    let second = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
    let onSecond = CGRect(x: 2000, y: 300, width: 240, height: 200)
    expect(WindowPlacement.onScreen(onSecond, screens: [screen, second]) == onSecond)
}

check("cascade stays on screen") {
    let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
    let size = CGSize(width: 240, height: 220)
    for index in 0..<300 {
        expect(visible.contains(WindowPlacement.cascade(index: index, size: size, in: visible)))
    }
}

check("popup placement") {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
    let size = CGSize(width: 380, height: 340)

    let leftSide = CGRect(x: 100, y: 500, width: 290, height: 170)
    let right = WindowPlacement.popupFrame(anchor: leftSide, size: size, screens: [screen])
    expect(right.minX == leftSide.maxX + 12)
    expect(right.maxY == leftSide.maxY)

    let rightSide = CGRect(x: 1140, y: 500, width: 290, height: 170)
    let left = WindowPlacement.popupFrame(anchor: rightSide, size: size, screens: [screen])
    expect(left.maxX == rightSide.minX - 12)

    let wide = CGRect(x: 200, y: 300, width: 1040, height: 300)
    expect(screen.contains(WindowPlacement.popupFrame(anchor: wide, size: size, screens: [screen])))

    let low = CGRect(x: 100, y: 10, width: 290, height: 100)
    expect(screen.contains(WindowPlacement.popupFrame(anchor: low, size: size, screens: [screen])))

    let second = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
    let onSecond = CGRect(x: 2000, y: 400, width: 290, height: 170)
    expect(second.contains(WindowPlacement.popupFrame(anchor: onSecond, size: size, screens: [screen, second])))
}

check("photo looks size correctly") {
    expect(WindowPlacement.photoHeight(width: 240, aspect: 1.3, look: .stamp) == 192)
    expect(WindowPlacement.photoHeight(width: 300, aspect: 1.5, look: .bare) == 200)
    expect(WindowPlacement.photoHeight(width: 224, aspect: 1.5, look: .jharokha) == 310)
    expect(WindowPlacement.photoHeight(width: 224, aspect: 0.5, look: .jharokha) == 310)

    let plain = WindowPlacement.photoHeight(width: 240, aspect: 1.3, look: .album)
    let captioned = WindowPlacement.photoHeight(width: 240, aspect: 1.3, look: .album, hasCaption: true)
    expect(captioned == plain + WindowPlacement.captionHeight)
    let bare = WindowPlacement.photoHeight(width: 240, aspect: 1.3, look: .bare)
    expect(WindowPlacement.photoHeight(width: 240, aspect: 1.3, look: .bare, hasCaption: true) == bare)

    for look in PhotoLook.allCases {
        for caption in [false, true] {
            let height = WindowPlacement.photoHeight(width: 600, aspect: 0.8, look: look, hasCaption: caption)
            let width = WindowPlacement.photoWidth(height: height, aspect: 0.8, look: look, hasCaption: caption)
            expect(abs(width - 600) <= 2)
        }
    }
}

check("export renders markdown and text") {
    var todo = Item(kind: .todo)
    todo.title = "Trip"
    todo.tasks = [TodoTask(text: "Pack", done: true), TodoTask(text: "Go")]
    expect(Exporter.render(todo, format: .markdown) == "# Trip\n\n- [x] Pack\n- [ ] Go\n")
    expect(Exporter.render(todo, format: .text) == "Trip\n\n[x] Pack\n[ ] Go\n")
}

check("export writes unique files, skips photos") {
    let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: parent) }
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

    var first = Item(kind: .note)
    first.title = "Same/Name"
    first.body = "one"
    var second = Item(kind: .note)
    second.title = "Same/Name"
    second.body = "two"
    let photo = Item(kind: .photo)

    let result = try Exporter.export([first, second, photo], format: .text, into: parent)
    let files = try FileManager.default.contentsOfDirectory(atPath: result.folder.path).sorted()
    expect(result.count == 2)
    expect(files == ["Same Name 2.txt", "Same Name.txt"])
}

check("URL commands parse") {
    expect(URLCommand(url: URL(string: "parchi://new?title=Hi&text=Hello%20world")!)
        == .newNote(title: "Hi", text: "Hello world"))
    expect(URLCommand(url: URL(string: "parchi://todo?title=T&items=a%0A%20b%0A%0Ac")!)
        == .newTodo(title: "T", items: ["a", "b", "c"]))
    expect(URLCommand(url: URL(string: "parchi://open")!) == .openMain)
    expect(URLCommand(url: URL(string: "https://new?title=x")!) == nil)
    expect(URLCommand(url: URL(string: "parchi://delete-everything")!) == nil)
}

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
