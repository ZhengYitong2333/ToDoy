import Foundation

struct Todo: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = ""
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
