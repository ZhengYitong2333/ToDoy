import SwiftUI
import WidgetKit

enum Scope: String, CaseIterable {
    case today = "我的一天", important = "重要", planned = "计划内", overdue = "已逾期", all = "全部", done = "已完成"
    var icon: String {
        switch self {
        case .today: return "sun.max"
        case .important: return "star"
        case .planned: return "calendar"
        case .overdue: return "clock.badge.exclamationmark"
        case .all: return "tray"
        case .done: return "checkmark.circle"
        }
    }
    func shows(_ t: Todo, now: Date) -> Bool {
        switch self {
        case .today: return t.inMyDay(on: now)
        case .important: return t.important
        case .planned: return t.due != nil && !t.isOverdue(on: now)
        case .overdue: return t.isOverdue(on: now)
        case .all: return true
        case .done: return t.completed
        }
    }
}

final class Store: ObservableObject {
    @Published private(set) var library = TaskLibrary()
    var items: [Todo] { library.items }
    var lists: [TaskList] { library.lists }
    let file: URL
    var didPersist: (([Todo]) -> Void)?
    private var readError: Error?
    init(file: URL) {
        self.file = file
        do { library = try TaskLibrary.load(Data(contentsOf: file)) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {}
        catch { readError = error }
    }
    private func persist(_ next: TaskLibrary) throws {
        if let readError { throw readError }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: file, options: .atomic)
        library = next
        didPersist?(next.items)
        if file.lastPathComponent == "tasks.json" && Bundle.main.bundleIdentifier == "local.desktop.todo.panel" {
            WidgetCenter.shared.reloadTimelines(ofKind: TodoWidgetID.kind)
        }
    }
    @discardableResult func change(_ edit: (inout [Todo]) -> Void) -> Bool {
        update { edit(&$0.items) }
    }
    func saveList(_ list: TaskList) -> Bool {
        update { library in
            if let index = library.lists.firstIndex(where: { $0.id == list.id }) { library.lists[index] = list }
            else { library.lists.append(list) }
        }
    }
    func removeList(_ id: UUID) -> Bool {
        update { library in
            library.lists.removeAll { $0.id == id }
            for i in library.items.indices where library.items[i].listID == id { library.items[i].listID = nil }
        }
    }
    private func update(_ edit: (inout TaskLibrary) -> Void) -> Bool {
        var next = library
        edit(&next)
        do { try persist(next); return true }
        catch { NSAlert(error: error).runModal(); return false }
    }
    func toggleCompletion(id: UUID) -> Bool? {
        guard var current = items.first(where: { $0.id == id }) else { return nil }
        current.completed.toggle()
        return save(current) ? current.completed : nil
    }
    func save(_ task: Todo) -> Bool {
        change { list in
            var task = task
            if let index = list.firstIndex(where: { $0.id == task.id }) {
                let previous = list[index]
                let now = Date()
                task.completedAt = task.completed ? (previous.completed ? previous.completedAt : now) : nil
                task.nextOccurrenceID = previous.nextOccurrenceID
                if task.recurrence != previous.recurrence || task.due != previous.due {
                    task.recurrenceAnchor = task.due ?? task.reminderAt ?? now
                }
                if task.completed && !previous.completed && task.nextOccurrenceID == nil,
                   let next = task.nextOccurrence(after: now) {
                    task.nextOccurrenceID = next.id
                    list.append(next)
                }
                list[index] = task
            } else {
                task.completedAt = task.completed ? Date() : nil
                list.insert(task, at: 0)
            }
        }
    }
}
