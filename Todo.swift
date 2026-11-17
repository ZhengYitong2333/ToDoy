import Foundation

struct Todo: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = ""
    var createdAt: Date? = Date()
    var due: Date?
    var important = false
    var completedAt: Date?
    var completed = false
    var day: Date?
    var note = ""
    var excludedFromMyDay: Date?
    var listID: UUID?

    func inMyDay(on date: Date) -> Bool {
        let calendar = Calendar.current
        if let excludedFromMyDay, calendar.isDate(excludedFromMyDay, inSameDayAs: date) { return false }
        return [day, due].compactMap { $0 }.contains { calendar.isDate($0, inSameDayAs: date) }
    }

    mutating func setMyDay(_ included: Bool, on date: Date = Date()) {
        day = included ? date : nil
        excludedFromMyDay = included ? nil : date
    }

    mutating func setDueDay(offset: Int) {
        let calendar = Calendar.current
        let now = Date()
        let target = calendar.date(byAdding: .day, value: offset, to: now) ?? now
        due = calendar.date(bySettingHour: due.map { calendar.component(.hour, from: $0) } ?? 18,
                            minute: due.map { calendar.component(.minute, from: $0) } ?? 0,
                            second: 0, of: target)
    }
}

enum TodoWidgetID {
    static let kind = "DesktopTodoList"
    static let relativeFile = "Library/Application Support/DesktopTodo/tasks.json"
}

struct TaskList: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
}

struct TaskLibrary: Codable {
    var items: [Todo] = []
    var lists = [TaskList(id: UUID(uuidString: "371CE4FB-A228-4E30-9BB1-3902C3A9532E")!, name: "工作内容"),
                 TaskList(id: UUID(uuidString: "49E8A3F0-DFE6-4085-92E9-E9D72F4DC9B2")!, name: "待买清单")]

    static func load(_ data: Data) throws -> TaskLibrary {
        let decoder = JSONDecoder()
        if let legacy = try? decoder.decode([Todo].self, from: data) { return TaskLibrary(items: legacy) }
        return try decoder.decode(TaskLibrary.self, from: data)
    }
}

enum TaskSort: String, CaseIterable, Codable {
    case defaultOrder = "默认顺序"
    case importance = "重要性"
    case title = "名称"
    case due = "到期日期"
    case created = "创建日期"

    var icon: String {
        switch self {
        case .defaultOrder: return "list.bullet"
        case .importance: return "star"
        case .title: return "textformat.abc"
        case .due: return "calendar"
        case .created: return "clock"
        }
    }

    func arrange(_ tasks: [Todo], completed: Bool = false) -> [Todo] {
        tasks.enumerated().sorted { left, right in
            let a = left.element, b = right.element
            switch self {
            case .defaultOrder:
                if completed, a.completedAt != b.completedAt { return (a.completedAt ?? .distantPast) > (b.completedAt ?? .distantPast) }
            case .importance:
                if a.important != b.important { return a.important }
            case .title:
                let comparison = a.title.localizedStandardCompare(b.title)
                if comparison != .orderedSame { return comparison == .orderedAscending }
            case .due:
                if a.due != b.due { return (a.due ?? .distantFuture) < (b.due ?? .distantFuture) }
            case .created:
                if a.createdAt != b.createdAt { return (a.createdAt ?? .distantPast) > (b.createdAt ?? .distantPast) }
            }
            return left.offset < right.offset
        }.map(\.element)
    }
}

struct ListDisplayOptions: Codable {
    var sort = TaskSort.defaultOrder
    var hideCompleted = false
}
