import Foundation
import UserNotifications

func runScheduleChecks() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 18) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
    let jan31 = date(2026, 1, 31)
    let noDate = Todo(title: "无截止时间")
    let futureTask = Todo(title: "未来", due: date(2026, 12, 1))
    let earlierTask = Todo(title: "较早逾期", due: date(2026, 11, 18))
    let laterTask = Todo(title: "较晚逾期", due: date(2026, 11, 20))
    let sameDate = Todo(title: "同一截止时间", due: laterTask.due)
    let unordered = [noDate, futureTask, laterTask, earlierTask, sameDate]
    let expectedOrder = [earlierTask, laterTask, sameDate, futureTask, noDate].map(\.id)
    precondition(ListDisplayOptions().sort == .due)
    precondition(TaskSort.due.arrange(unordered).map(\.id) == expectedOrder)
    precondition(TaskSort.defaultOrder.arrange(unordered).map(\.id) == expectedOrder)
    let oldOrder = try JSONDecoder().decode(ListDisplayOptions.self, from: Data("{\"sort\":\"默认顺序\",\"hideCompleted\":true}".utf8))
    precondition(oldOrder.sort.arrange(unordered).map(\.id) == expectedOrder && oldOrder.hideCompleted)
    precondition(ScheduleMenuDates.nextMonday(from: date(2026, 11, 22), calendar: calendar) == date(2026, 11, 23, 9))
    precondition(ScheduleMenuDates.nextMonday(from: date(2026, 11, 23, 8), calendar: calendar) == date(2026, 11, 30, 9))
    let feb28 = date(2026, 2, 28)
    precondition(RecurrenceRule.monthly.nextDate(after: jan31, anchor: jan31, calendar: calendar) == feb28)
    precondition(RecurrenceRule.monthly.nextDate(after: feb28, anchor: jan31, calendar: calendar) == date(2026, 3, 31))
    let leap = date(2024, 2, 29)
    precondition(RecurrenceRule.yearly.nextDate(after: leap, anchor: leap, calendar: calendar) == date(2025, 2, 28))
    precondition(RecurrenceRule.yearly.nextDate(after: date(2027, 2, 28), anchor: leap, calendar: calendar) == date(2028, 2, 29))
    let friday = date(2026, 11, 20)
    precondition(RecurrenceRule.weekdays.nextDate(after: friday, anchor: friday, calendar: calendar) == date(2026, 11, 23))
    precondition(RecurrenceRule.weekly.nextDate(after: date(2026, 12, 1), anchor: friday, calendar: calendar) == date(2026, 12, 4))
    precondition(RecurrenceRule.daily.nextDate(after: date(2026, 11, 22, 12), anchor: friday, calendar: calendar) == date(2026, 11, 22))
    var pacific = Calendar(identifier: .gregorian)
    pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let beforeDST = pacific.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 9))!
    let afterDST = RecurrenceRule.daily.nextDate(after: beforeDST, anchor: beforeDST, calendar: pacific)!
    precondition(pacific.component(.hour, from: afterDST) == 9 && afterDST.timeIntervalSince(beforeDST) == 23 * 3600)

    var repeated = Todo(title: "每月复盘", due: jan31, important: true, day: jan31, note: "保留备注",
                        listID: UUID(), reminderAt: jan31.addingTimeInterval(-3600), recurrence: .monthly)
    let next = repeated.nextOccurrence(after: jan31, calendar: calendar)!
    precondition(next.due == feb28 && next.reminderAt == feb28.addingTimeInterval(-3600))
    precondition(next.id != repeated.id && next.title == repeated.title && next.note == repeated.note && next.listID == repeated.listID && next.important)
    precondition(!next.completed && next.completedAt == nil && next.day == nil && next.excludedFromMyDay == nil)
    precondition(next.nextOccurrence(after: feb28, calendar: calendar)?.due == date(2026, 3, 31))
    repeated.recurrence = nil
    precondition(repeated.nextOccurrence(after: jan31, calendar: calendar) == nil)

    let legacy = Data("{\"id\":\"371CE4FB-A228-4E30-9BB1-3902C3A9532E\",\"title\":\"旧任务\",\"important\":false,\"completed\":false,\"note\":\"\"}".utf8)
    let old = try JSONDecoder().decode(Todo.self, from: legacy)
    precondition(old.recurrence == nil && old.reminderAt == nil && old.nextOccurrenceID == nil)
    let restored = try JSONDecoder().decode(Todo.self, from: JSONEncoder().encode(next))
    precondition(restored == next)

    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = Store(file: folder.appendingPathComponent("schedule-check.json"))
    let now = Date()
    let series = Todo(title: "每日任务", due: now.addingTimeInterval(3600), reminderAt: now.addingTimeInterval(1800), recurrence: .daily)
    precondition(store.save(series))
    precondition(store.toggleCompletion(id: series.id) == true)
    precondition(store.items.count == 2)
    let completed = store.items.first { $0.id == series.id }!
    let child = store.items.first { $0.id == completed.nextOccurrenceID }!
    precondition(child.due! > series.due! && !child.completed)
    precondition(child.reminderAt!.timeIntervalSince(child.due!) == -1800)
    precondition(store.save(completed) && store.items.count == 2)
    precondition(store.toggleCompletion(id: series.id) == false)
    precondition(store.toggleCompletion(id: series.id) == true && store.items.count == 2)
    precondition(Store(file: store.file).items == store.items)
    var stop = child
    stop.recurrence = nil
    precondition(store.save(stop))
    precondition(store.toggleCompletion(id: stop.id) == true && store.items.count == 2)

    let alert = Todo(title: "未来提醒", reminderAt: now.addingTimeInterval(3600))
    var done = alert; done.completed = true
    var past = alert; past.reminderAt = now.addingTimeInterval(-1)
    var cleared = alert; cleared.reminderAt = nil
    precondition(ReminderService.requests(for: [done, past, cleared], now: now).isEmpty)
    let request = ReminderService.requests(for: [alert], now: now).first!
    precondition(request.identifier == ReminderService.prefix + alert.id.uuidString && request.content.body == alert.title)
    precondition(request.content.userInfo["taskID"] as? String == alert.id.uuidString)
    let trigger = request.trigger as! UNCalendarNotificationTrigger
    precondition(!trigger.repeats && abs(trigger.nextTriggerDate()!.timeIntervalSince(alert.reminderAt!)) < 1)
    var changed = alert; changed.title = "已改名"; changed.reminderAt = now.addingTimeInterval(7200)
    let replacement = ReminderService.requests(for: [changed], now: now).first!
    precondition(replacement.identifier == request.identifier && replacement.content.body == "已改名")
    precondition((replacement.trigger as! UNCalendarNotificationTrigger).dateComponents != trigger.dateComponents)
    precondition(ReminderService.requests(for: [], now: now).isEmpty)
    print("Recurrence, leap year, month-end, DST, idempotency, legacy data and reminder request checks OK")
}
