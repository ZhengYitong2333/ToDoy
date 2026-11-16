import SwiftUI
import WidgetKit
import Darwin

struct Entry: TimelineEntry {
    let date = Date()
    let tasks: [Todo]
    var lastCompleted: Todo?
    var unavailable = false
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(tasks: [Todo(title: "整理今日计划"), Todo(title: "回顾本周进度")])
    }
    func load() -> Entry {
        guard let home = getpwuid(getuid())?.pointee.pw_dir else { return Entry(tasks: [], unavailable: true) }
        let file = URL(fileURLWithPath: String(cString: home)).appendingPathComponent(TodoWidgetID.relativeFile)
        do {
            let tasks = try TaskLibrary.load(Data(contentsOf: file)).items
            let last = tasks.filter { $0.completed && $0.completedAt != nil }
                .max { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
            return Entry(tasks: tasks.filter { !$0.completed }, lastCompleted: last)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return Entry(tasks: [])
        } catch { return Entry(tasks: [], unavailable: true) }
    }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : load())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [load()], policy: .after(Date().addingTimeInterval(3600))))
    }
}

struct ListFace: View {
    @Environment(\.widgetFamily) var family
    let entry: Entry
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "checklist").foregroundStyle(.mint)
                Text("ToDoy").bold()
                Spacer()
                Text("\(entry.tasks.count)").font(.headline).foregroundStyle(.secondary)
                if family != .systemSmall {
                    Link(destination: URL(string: "local-desktop-todo://new")!) {
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.mint)
                            .frame(width: 40, height: 34).contentShape(Rectangle())
                    }.accessibilityLabel("添加任务")
                }
            }
            Divider()
            if entry.tasks.isEmpty {
                Spacer()
                Text(entry.unavailable ? "打开待办查看任务" : "暂无待办").foregroundStyle(.secondary)
            }
            ForEach(entry.tasks.prefix(family == .systemLarge ? 7 : entry.lastCompleted == nil ? 3 : 2)) { task in
                let row = HStack(spacing: 6) {
                    Image(systemName: task.important ? "star.fill" : "circle").font(.caption).foregroundStyle(.mint)
                    Text(task.title).lineLimit(1)
                    Spacer(minLength: 0)
                    if family != .systemSmall, let date = task.due {
                        Text(date, format: .dateTime.month().day().hour().minute()).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if family == .systemSmall { row }
                else { Link(destination: URL(string: "local-desktop-todo://task/\(task.id)")!) { row.frame(maxWidth: .infinity, minHeight: 24).contentShape(Rectangle()) } }
            }
            Spacer(minLength: 0)
            if let task = entry.lastCompleted, let time = task.completedAt {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.mint)
                    if family != .systemSmall { Text(task.title).lineLimit(1) }
                    Text("完成").fixedSize()
                    Text(time, format: .dateTime.month().day().hour().minute()).lineLimit(1)
                }.font(.caption2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(.primary)
        .widgetURL(URL(string: "local-desktop-todo://board"))
        .containerBackground(for: .widget) {
            ZStack {
                ContainerRelativeShape().fill(.ultraThinMaterial)
                LinearGradient(colors: [.teal.opacity(0.16), .clear, .indigo.opacity(0.18)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                ContainerRelativeShape()
                    .strokeBorder(.white.opacity(0.24), lineWidth: 0.75)
            }
        }
    }
}

@main struct TodoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TodoWidgetID.kind, provider: Provider()) { ListFace(entry: $0) }
            .contentMarginsDisabled()
            .configurationDisplayName("ToDoy")
            .description("查看未完成的任务和截止时间。")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
