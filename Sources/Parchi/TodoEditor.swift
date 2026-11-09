import AppKit
import ParchiCore
import SwiftUI

/// The editable to-do list, used in the popup and the main window.
struct TodoEditor: View {
    let model: ItemModel
    let services: AppServices
    var autoFocus = false

    @FocusState private var focusedTask: String?

    private var store: Store { services.store }

    private var shown: [TodoTask] {
        TodoOrdering.display(model.item.tasks, completedLast: services.settings.values.moveCompletedToBottom)
    }

    var body: some View {
        let item = model.item
        let theme = CardTheme.find(item.themeID)
        let font = Font(NoteFont.body(item) as CTFont)

        List {
            ForEach(shown) { task in
                row(task, font: font, ink: theme.inkColor, square: theme.squareChecks)
                    .listRowInsets(EdgeInsets(top: 3, leading: 11, bottom: 3, trailing: 11))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .onMove(perform: move)

            Button {
                addTask(after: nil)
            } label: {
                Label("Add to-do", systemImage: "plus")
                    .font(.system(size: 12))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.inkColor.opacity(0.65))
            .listRowInsets(EdgeInsets(top: 3, leading: 11, bottom: 3, trailing: 11))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .moveDisabled(true)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 20)
        .onAppear {
            if autoFocus { focusLast() }
        }
    }

    private func row(_ task: TodoTask, font: Font, ink: Color, square: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button {
                toggle(task.id)
            } label: {
                Image(systemName: square ? (task.done ? "checkmark.square" : "square") : (task.done ? "checkmark.circle.fill" : "circle"))
                    .font(.system(size: CGFloat(model.item.fontSize)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(ink.opacity(task.done ? 0.5 : 0.8))

            TextField("To-do", text: textBinding(task.id), prompt: Text("To-do").foregroundStyle(ink.opacity(0.35)), axis: .vertical)
                .textFieldStyle(.plain)
                .font(font)
                .foregroundStyle(ink.opacity(task.done ? 0.45 : 1))
                .strikethrough(task.done, color: ink.opacity(0.5))
                .focused($focusedTask, equals: task.id)
                .onSubmit { addTask(after: task.id) }
                .onKeyPress(.delete) {
                    guard task.text.isEmpty, model.item.tasks.count > 1 else { return .ignored }
                    remove(task.id)
                    return .handled
                }

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9))
                .foregroundStyle(ink.opacity(0.3))
                .help("Drag to reorder")

            Button {
                remove(task.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(ink.opacity(0.4))
            .help("Delete")
        }
    }

    private func textBinding(_ id: String) -> Binding<String> {
        Binding(
            get: { model.item.tasks.first { $0.id == id }?.text ?? "" },
            set: { text in
                store.update(model) { item in
                    guard let index = item.tasks.firstIndex(where: { $0.id == id }) else { return }
                    // A pasted multi-line block becomes separate tasks.
                    let lines = text.split(whereSeparator: \.isNewline).map(String.init)
                    guard lines.count > 1 else {
                        item.tasks[index].text = text.replacingOccurrences(of: "\n", with: "")
                        return
                    }
                    item.tasks[index].text = lines[0]
                    item.tasks.insert(contentsOf: lines.dropFirst().map { TodoTask(text: $0) }, at: index + 1)
                }
            }
        )
    }

    private func toggle(_ id: String) {
        store.update(model) { item in
            guard let index = item.tasks.firstIndex(where: { $0.id == id }) else { return }
            item.tasks[index].done.toggle()
        }
    }

    private func addTask(after id: String?) {
        let task = TodoTask()
        store.update(model) { item in
            if let id, let index = item.tasks.firstIndex(where: { $0.id == id }) {
                item.tasks.insert(task, at: index + 1)
            } else {
                // Keep new tasks above completed ones when those sit at the bottom.
                let completedLast = services.settings.values.moveCompletedToBottom
                let index = completedLast ? (item.tasks.lastIndex { !$0.done }.map { $0 + 1 } ?? 0) : item.tasks.count
                item.tasks.insert(task, at: index)
            }
        }
        focusSoon(task.id)
    }

    private func remove(_ id: String) {
        let order = shown.map(\.id)
        let previous = order.firstIndex(of: id).flatMap { $0 > 0 ? order[$0 - 1] : nil }
        store.update(model) { item in
            item.tasks.removeAll { $0.id == id }
        }
        if let previous { focusSoon(previous) }
    }

    private func move(from offsets: IndexSet, to destination: Int) {
        var reordered = shown
        reordered.move(fromOffsets: offsets, toOffset: destination)
        store.update(model) { $0.tasks = reordered }
    }

    private func focusLast() {
        if let last = shown.last(where: { !$0.done }) ?? shown.last {
            focusSoon(last.id)
        }
    }

    /// Waits a tick so that a row just added exists before it takes focus.
    private func focusSoon(_ id: String) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(30))
            focusedTask = id
        }
    }
}
