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
    var reminderAt: Date?
    var recurrence: RecurrenceRule?
    var recurrenceAnchor: Date?
    var nextOccurrenceID: UUID?

    func nextOccurrence(after date: Date, calendar: Calendar = .current) -> Todo? {
        guard let recurrence else { return nil }
        let base = due ?? reminderAt ?? date
        let anchor = recurrenceAnchor ?? base
        guard let nextDate = recurrence.nextDate(after: max(date, base), anchor: anchor, calendar: calendar) else { return nil }
        var next = self
        next.id = UUID()
        next.createdAt = date
        next.due = nextDate
        next.reminderAt = reminderAt.map { nextDate.addingTimeInterval($0.timeIntervalSince(base)) }
        next.recurrenceAnchor = anchor
        next.completed = false
        next.completedAt = nil
        next.day = nil
        next.excludedFromMyDay = nil
        next.nextOccurrenceID = nil
        return next
    }

    func isOverdue(on date: Date) -> Bool {
        !completed && due.map { $0 < date } == true
    }

    func inMyDay(on date: Date) -> Bool {
        let calendar = Calendar.current
        if let excludedFromMyDay, calendar.isDate(excludedFromMyDay, inSameDayAs: date) { return false }
        if [day, due].compactMap({ $0 }).contains(where: { calendar.isDate($0, inSameDayAs: date) }) { return true }
        if isOverdue(on: date) { return true }
        // Keep overdue tasks completed today visible through the celebration and completed group.
        if completed, let due, due < date, let completedAt {
            return calendar.isDate(completedAt, inSameDayAs: date)
        }
        return false
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

enum RecurrenceRule: String, Codable, CaseIterable {
    case daily, weekdays, weekly, monthly, yearly

    var title: String {
        switch self {
        case .daily: return "每天"
        case .weekdays: return "工作日（周一至周五）"
        case .weekly: return "每周"
        case .monthly: return "每月"
        case .yearly: return "每年"
        }
    }

    func nextDate(after date: Date, anchor: Date, calendar: Calendar = .current) -> Date? {
        let time = calendar.dateComponents([.hour, .minute, .second], from: anchor)
        func atTime(_ day: Date) -> Date? {
            calendar.date(bySettingHour: time.hour ?? 18, minute: time.minute ?? 0, second: time.second ?? 0, of: day)
        }
        switch self {
        case .daily, .weekdays, .weekly:
            guard var candidate = atTime(date) else { return nil }
            if self == .weekly {
                let offset = (calendar.component(.weekday, from: anchor) - calendar.component(.weekday, from: date) + 7) % 7
                guard let adjusted = calendar.date(byAdding: .day, value: offset, to: candidate) else { return nil }
                candidate = adjusted
            }
            if candidate <= date {
                guard let adjusted = calendar.date(byAdding: .day, value: self == .weekly ? 7 : 1, to: candidate) else { return nil }
                candidate = adjusted
            }
            while self == .weekdays && [1, 7].contains(calendar.component(.weekday, from: candidate)) {
                guard let adjusted = calendar.date(byAdding: .day, value: 1, to: candidate) else { return nil }
                candidate = adjusted
            }
            return candidate
        case .monthly, .yearly:
            let unit: Calendar.Component = self == .monthly ? .month : .year
            guard var period = calendar.dateInterval(of: unit, for: date)?.start else { return nil }
            for _ in 0..<2 {
                var components = calendar.dateComponents([.era, .year, .month], from: period)
                if self == .yearly { components.month = calendar.component(.month, from: anchor) }
                components.day = 1
                guard let month = calendar.date(from: components), let days = calendar.range(of: .day, in: .month, for: month) else { return nil }
                components.day = min(calendar.component(.day, from: anchor), days.count)
                components.hour = time.hour; components.minute = time.minute; components.second = time.second
                guard let candidate = calendar.date(from: components) else { return nil }
                if candidate > date { return candidate }
                guard let next = calendar.date(byAdding: unit, value: 1, to: period) else { return nil }
                period = next
            }
            return nil
        }
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

    // Keep the old value decodable while presenting one default date order in the menu.
    static let allCases: [TaskSort] = [.due, .importance, .title, .created]

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
            case .defaultOrder, .due:
                switch (a.due, b.due) {
                case let (first?, second?) where first != second: return first < second
                case (_?, nil): return true
                case (nil, _?): return false
                default: break
                }
            case .importance:
                if a.important != b.important { return a.important }
            case .title:
                let comparison = a.title.localizedStandardCompare(b.title)
                if comparison != .orderedSame { return comparison == .orderedAscending }
            case .created:
                if a.createdAt != b.createdAt { return (a.createdAt ?? .distantPast) > (b.createdAt ?? .distantPast) }
            }
            return left.offset < right.offset
        }.map(\.element)
    }
}

struct ListDisplayOptions: Codable {
    var sort = TaskSort.due
    var hideCompleted = false
}
