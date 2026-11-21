import SwiftUI

struct ReminderStatus: View {
    @ObservedObject var service: ReminderService
    var body: some View {
        if let message = service.message {
            VStack(alignment: .leading, spacing: 6) {
                Text(message).font(.caption).foregroundStyle(.red)
                Button("打开通知设置", action: ReminderService.openSettings).foregroundStyle(.teal)
            }.padding(.bottom, 10)
        }
    }
}

struct ScheduleMenuDates {
    static func nextMonday(from now: Date, calendar: Calendar = .current) -> Date {
        let offset = (9 - calendar.component(.weekday, from: now)) % 7
        let day = calendar.date(byAdding: .day, value: offset == 0 ? 7 : offset, to: now) ?? now
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }
}

struct InspectorScheduleRow: View {
    let icon: String
    let title: String
    var color: Color = .secondary
    let action: () -> Void
    var clear: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 12) {
                    Image(systemName: icon).font(.system(size: 17)).frame(width: 20)
                    Text(title).lineLimit(2).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, minHeight: 48).contentShape(Rectangle())
            }.foregroundStyle(color)
            if let clear {
                Button(action: clear) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary).frame(width: 30, height: 40).contentShape(Rectangle())
                }.accessibilityLabel("清除" + title).help("清除")
            }
        }.buttonStyle(.plain)
    }
}

private struct ScheduleMenuItem: View {
    let icon: String
    let title: String
    var detail: String = ""
    var selected = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 18).foregroundStyle(.secondary)
                Text(title)
                Spacer(minLength: 8)
                if selected { Image(systemName: "checkmark").foregroundStyle(.teal) }
                else if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }.font(.system(size: 13)).padding(.horizontal, 12).frame(minHeight: 40)
                .contentShape(Rectangle())
                .background(hovered ? Color.primary.opacity(0.055) : .clear, in: RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain).onHover { hovered = $0 }
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ReminderOptions: View {
    @Binding var date: Date?
    @ObservedObject var service: ReminderService
    let close: () -> Void
    @State private var custom = false
    @State private var busy = false
    @State private var visible = true
    @State private var error: String?

    var body: some View {
        Group {
            if custom {
                DateTimeOptions(date: $date, isReminder: true,
                                authorize: { await service.requestPermission() }, close: close)
            } else {
                let now = Date()
                let later = Calendar.current.dateInterval(of: .minute, for: now.addingTimeInterval(3600))?.start ?? now.addingTimeInterval(3600)
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
                let morning = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
                let nextWeek = ScheduleMenuDates.nextMonday(from: now)
                VStack(alignment: .leading, spacing: 0) {
                    Text("提醒我").font(.system(size: 13, weight: .semibold)).padding(12)
                    Divider().padding(.horizontal, 6)
                    ScheduleMenuItem(icon: "clock", title: "稍后", detail: later.formatted(.dateTime.hour().minute())) { set(later) }
                    ScheduleMenuItem(icon: "sun.max", title: "明天", detail: "09:00") { set(morning) }
                    ScheduleMenuItem(icon: "calendar", title: "下周", detail: "周一 09:00") { set(nextWeek) }
                    Divider().padding(.horizontal, 6)
                    ScheduleMenuItem(icon: "calendar.badge.clock", title: "选择日期和时间…") { custom = true }
                    if date != nil {
                        Divider().padding(.horizontal, 6)
                        ScheduleMenuItem(icon: "bell.slash", title: "删除提醒") { date = nil; close() }
                    }
                    if busy { ProgressView().controlSize(.small).padding(12) }
                    if let error { Text(error).font(.caption).foregroundStyle(.red).padding(12) }
                    ReminderStatus(service: service).padding(.horizontal, 12)
                }.padding(6).frame(width: 288).disabled(busy)
            }
        }.onAppear { visible = true }.onDisappear { visible = false }
    }

    private func set(_ value: Date) {
        busy = true
        Task { @MainActor in
            defer { busy = false }
            guard await service.requestPermission() else {
                error = service.message ?? "通知未开启，请在系统设置中允许 ToDoy 发送通知。"
                return
            }
            guard visible else { return }
            guard value > Date() else { error = "该时间已过，请重新选择。"; return }
            date = value
            close()
        }
    }
}

struct DeadlineOptions: View {
    @Binding var task: Todo
    let close: () -> Void
    @State private var custom = false

    var body: some View {
        if custom {
            DateTimeOptions(date: $task.due, close: close)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("截止日期").font(.system(size: 13, weight: .semibold)).padding(12)
                Divider().padding(.horizontal, 6)
                ScheduleMenuItem(icon: "sun.max", title: "今天") { setDay(0) }
                ScheduleMenuItem(icon: "sunrise", title: "明天") { setDay(1) }
                ScheduleMenuItem(icon: "calendar", title: "下周", detail: "周一") {
                    let calendar = Calendar.current
                    let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()),
                                                         to: calendar.startOfDay(for: ScheduleMenuDates.nextMonday(from: Date()))).day ?? 7
                    setDay(offset)
                }
                Divider().padding(.horizontal, 6)
                ScheduleMenuItem(icon: "calendar.badge.clock", title: "选择日期和时间…") { custom = true }
                if task.due != nil {
                    Divider().padding(.horizontal, 6)
                    ScheduleMenuItem(icon: "calendar.badge.minus", title: "删除截止日期") { task.due = nil; close() }
                }
            }.padding(6).frame(width: 288)
        }
    }

    private func setDay(_ offset: Int) { task.setDueDay(offset: offset); close() }
}

struct RecurrenceOptions: View {
    @Binding var task: Todo
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("重复").font(.system(size: 13, weight: .semibold)).padding(12)
            Divider().padding(.horizontal, 6)
            ForEach(RecurrenceRule.allCases, id: \.self) { rule in
                ScheduleMenuItem(icon: rule == .weekdays ? "briefcase" : "repeat", title: rule.title,
                                 selected: task.recurrence == rule) { apply(rule) }
            }
            Divider().padding(.horizontal, 6)
            ScheduleMenuItem(icon: "minus.circle", title: "不重复", selected: task.recurrence == nil) { apply(nil) }
        }.padding(6).frame(width: 288)
    }

    private func apply(_ rule: RecurrenceRule?) {
        task.recurrence = rule
        if rule != nil && task.due == nil {
            task.setDueDay(offset: 0)
            if task.isOverdue(on: Date()) { task.setDueDay(offset: 1) }
        }
        close()
    }
}
