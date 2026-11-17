import SwiftUI
import WidgetKit
import Darwin

struct Entry: TimelineEntry {
    var date = Date()
    static let completionNoticeDuration: TimeInterval = 8
    let tasks: [Todo]
    var lastCompleted: Todo?
    var unavailable = false
    var background: NSImage?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(tasks: [Todo(title: "整理今日计划"), Todo(title: "回顾本周进度")])
    }
    func load() -> Entry {
        guard let home = getpwuid(getuid())?.pointee.pw_dir else { return Entry(tasks: [], unavailable: true) }
        let file = URL(fileURLWithPath: String(cString: home)).appendingPathComponent(TodoWidgetID.relativeFile)
        let background = NSImage(contentsOf: file.deletingLastPathComponent().appendingPathComponent("WidgetBackground.jpg"))
        do {
            let tasks = try TaskLibrary.load(Data(contentsOf: file)).items
            let now = Date()
            let last = tasks.filter {
                guard $0.completed, let completedAt = $0.completedAt else { return false }
                return completedAt <= now && now < completedAt.addingTimeInterval(Entry.completionNoticeDuration)
            }.max { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
            return Entry(tasks: tasks.filter { !$0.completed }, lastCompleted: last, background: background)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return Entry(tasks: [], background: background)
        } catch { return Entry(tasks: [], unavailable: true, background: background) }
    }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : load())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = load()
        var entries = [entry]
        if let completedAt = entry.lastCompleted?.completedAt {
            var cleared = entry
            cleared.date = completedAt.addingTimeInterval(Entry.completionNoticeDuration)
            cleared.lastCompleted = nil
            entries.append(cleared)
        }
        completion(Timeline(entries: entries, policy: .after(Date().addingTimeInterval(3600))))
    }
}

struct ListFace: View {
    @Environment(\.widgetFamily) var family
    let entry: Entry
    private var visibleLimit: Int { family == .systemLarge ? 9 : 3 }
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
            ForEach(entry.tasks.prefix(visibleLimit)) { task in
                let row = HStack(spacing: 6) {
                    Image(systemName: task.important ? "star.fill" : "circle").font(.caption).foregroundStyle(.mint)
                    Text(task.title).lineLimit(1)
                    Spacer(minLength: 0)
                    if family != .systemSmall, let date = task.due {
                        Text(date, format: .dateTime.month().day().hour().minute()).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if family == .systemSmall { row.frame(minHeight: 24) }
                else { Link(destination: URL(string: "local-desktop-todo://task/\(task.id)")!) { row.frame(maxWidth: .infinity, minHeight: 24).contentShape(Rectangle()) } }
            }
            Spacer(minLength: 0)
            if entry.tasks.count > visibleLimit {
                Link(destination: URL(string: "local-desktop-todo://board")!) {
                    Text("还有 \(entry.tasks.count - visibleLimit) 项待办 ›")
                        .font(.caption2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let task = entry.lastCompleted, let time = task.completedAt {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.mint)
                    if family != .systemSmall { Text(task.title).lineLimit(1) }
                    Text("完成").fixedSize()
                    Text(time, format: .dateTime.month().day().hour().minute()).lineLimit(1)
                }.font(.caption2).lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(entry.background == nil ? Color.primary : Color.white)
        .widgetURL(URL(string: "local-desktop-todo://board"))
        .containerBackground(for: .widget) {
            ZStack {
                if let image = entry.background {
                    GeometryReader { geometry in
                        Image(nsImage: image).resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    }
                } else {
                    ContainerRelativeShape().fill(.ultraThinMaterial)
                    LinearGradient(colors: [.teal.opacity(0.16), .clear, .indigo.opacity(0.18)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
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
