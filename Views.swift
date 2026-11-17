import SwiftUI

private struct SurfaceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.contentShape(Rectangle())
    }
}

func iconButton(_ symbol: String, _ title: String, _ action: @escaping () -> Void) -> some View {
    Button(action: action) { Image(systemName: symbol).font(.system(size: 17, weight: .medium)).frame(width: 44, height: 44).contentShape(Rectangle()) }
        .buttonStyle(SurfaceButtonStyle()).accessibilityLabel(title).help(title)
}

struct TaskRow: View {
    let burst: CompletionBurst?
    let onCompletionChange: (UUID, Bool) -> Void
    @State private var confirmDelete = false
    let task: Todo
    let app: Controller
    var body: some View {
        HStack(spacing: 2) {
            iconButton(task.completed ? "checkmark.circle.fill" : "circle", task.completed ? "重新打开" : "完成任务", toggleCompletion)
            .overlay {
                if let burst { CompletionFirework(burst: burst) }
            }.zIndex(burst == nil ? 0 : 1)
            Button { app.edit(task) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title).lineLimit(1).strikethrough(task.completed)
                    if let completed = task.completedAt {
                        Text("完成于 \(completed.formatted(.dateTime.year().month().day().hour().minute()))")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if let due = task.due {
                        Text(due, format: .dateTime.year().month().day().hour().minute())
                            .font(.caption).foregroundStyle(due < Date() && !task.completed ? Color.red : .secondary)
                    }
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(SurfaceButtonStyle())
            iconButton(task.important ? "star.fill" : "star", task.important ? "取消重要" : "标为重要", toggleImportance)
                .foregroundStyle(task.important ? Color.orange : .secondary)
        }
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .contextMenu {
            Button(task.inMyDay(on: Date()) ? "从“我的一天”移除" : "加入“我的一天”", systemImage: "sun.max") {
                var copy = task
                copy.setMyDay(!task.inMyDay(on: Date()))
                _ = app.store.save(copy)
            }
            Button(task.important ? "取消重要标记" : "标记为重要", systemImage: "star", action: toggleImportance)
            Button(task.completed ? "标记为未完成" : "标记为已完成", systemImage: "checkmark.circle", action: toggleCompletion)
            Divider()
            Button("今天到期", systemImage: "calendar") { setDueDay(0) }
            Button("明天到期", systemImage: "calendar.badge.clock") { setDueDay(1) }
            Button("选择截止日期和时间…", systemImage: "calendar") { app.edit(task) }
            if task.due != nil {
                Button("清除截止时间", systemImage: "calendar.badge.minus") {
                    var copy = task
                    copy.due = nil
                    _ = app.store.save(copy)
                }
            }
            Divider()
            Menu("移动到列表") {
                Button("无列表") { move(to: nil) }.disabled(task.listID == nil)
                ForEach(app.store.lists) { list in
                    Button(list.name) { move(to: list.id) }.disabled(task.listID == list.id)
                }
            }
            Button("编辑任务…", systemImage: "pencil") { app.edit(task) }
            Button("删除任务…", systemImage: "trash", role: .destructive) { confirmDelete = true }
        }
        .alert("删除“\(task.title)”？", isPresented: $confirmDelete) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { _ = app.store.change { $0.removeAll { $0.id == task.id } } }
        }
    }
    private func move(to id: UUID?) {
        var copy = task
        copy.listID = id
        _ = app.store.save(copy)
    }
    private func toggleCompletion() {
        if let done = app.store.toggleCompletion(id: task.id) { onCompletionChange(task.id, done) }
    }
    private func toggleImportance() {
        var copy = task
        copy.important.toggle()
        _ = app.store.save(copy)
    }
    private func setDueDay(_ offset: Int) {
        var copy = task
        copy.setDueDay(offset: offset)
        _ = app.store.save(copy)
    }
}

private let windowDragStripHeight: CGFloat = 30

struct Board: View {
    @ObservedObject var store: Store
    @ObservedObject var app: Controller
    @State private var scope = Scope.today
    @State private var selectedList: UUID?
    @State private var listEditor: TaskList?
    @State private var pendingRemoval: TaskList?
    @State private var query = ""
    @State private var today = Date()
    @State private var completedExpanded = true
    @State private var bursts: [CompletionBurst] = []
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Label("ToDoy", systemImage: "checklist").font(.title3.bold())
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                TextField("搜索任务", text: $query).textFieldStyle(.roundedBorder)
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Scope.allCases, id: \.self) { item in
                            sidebarButton(item.rawValue, icon: item.icon, selected: selectedList == nil && scope == item) {
                                selectedList = nil; scope = item; query = ""; completedExpanded = true
                            }
                        }
                        Divider()
                        ForEach(store.lists) { list in
                            sidebarButton(list.name, icon: "list.bullet", selected: selectedList == list.id) { select(list) }
                                .contextMenu {
                                    Button("重命名列表…") { listEditor = list }
                                    Button("删除列表…", role: .destructive) { pendingRemoval = list }
                                }
                        }
                    }
                }
                Button { listEditor = TaskList(name: "") } label: {
                    Label("新建列表", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                }.buttonStyle(SurfaceButtonStyle())
            }.padding(14).padding(.top, windowDragStripHeight).frame(width: 180).background(.regularMaterial)
            VStack(alignment: .leading, spacing: 12) {
                Text(query.isEmpty ? (store.lists.first { $0.id == selectedList }?.name ?? scope.rawValue) : "搜索结果").font(.system(size: 32, weight: .bold))
                Text(today, format: .dateTime.month().day().weekday(.wide)).font(.subheadline)
                ScrollView { VStack(spacing: 5) {
                    let rows = store.items.filter { query.isEmpty ? (selectedList == nil ? scope.shows($0, now: today) : $0.listID == selectedList) : $0.title.localizedCaseInsensitiveContains(query) || $0.note.localizedCaseInsensitiveContains(query) }
                    let celebrating = Set(bursts.map(\.taskID))
                    let completed = rows.filter { $0.completed && !celebrating.contains($0.id) }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
                    let pending = rows.filter { !$0.completed || celebrating.contains($0.id) }
                    let groupCompleted = scope != .done || !query.isEmpty
                    ForEach(pending) { task in
                        taskRow(task)
                    }
                    if !completed.isEmpty && groupCompleted {
                        Button { completedExpanded.toggle() } label: {
                            HStack(spacing: 6) {
                                Image(systemName: completedExpanded ? "chevron.down" : "chevron.right")
                                Text("已完成 · \(completed.count)")
                            }.font(.subheadline.bold()).padding(.horizontal, 10).frame(height: 29)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !groupCompleted || completedExpanded {
                        ForEach(completed) { task in
                            taskRow(task)
                        }
                    }
                    if rows.isEmpty { Text(query.isEmpty ? "暂无任务" : "没有匹配的任务").padding(.top, 28).foregroundStyle(.white) }
                } }.id(selectedList?.uuidString ?? scope.rawValue)
                TaskComposer(scope: scope, listID: selectedList, app: app) {
                    query = ""
                    if scope == .done { scope = .all }
                }.id(selectedList?.uuidString ?? scope.rawValue)
            }.padding(24).padding(.top, windowDragStripHeight)
            .background {
                GeometryReader { geo in
                    ZStack { Color.teal
                        if let picture = NSImage(named: "Landscape") {
                            Image(nsImage: picture).resizable().scaledToFill()
                        }
                        Color.black.opacity(0.25)
                    }.frame(width: geo.size.width, height: geo.size.height).clipped()
                }
            }
            .environment(\.colorScheme, .dark)
            if let detail = app.detail {
                Divider()
                TaskInspector(detail: detail, app: app, completionChanged: completionChanged)
                    .id(detail.task.id)
                    .frame(width: 300)
            }
        }
        .overlay(alignment: .top) {
            Color.clear.frame(height: windowDragStripHeight)
                .contentShape(Rectangle()).gesture(WindowDragGesture()).accessibilityHidden(true)
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 680, minHeight: 420)
        .onChange(of: store.items.map(\.id)) { _, ids in
            if let detail = app.detail, detail.existing, !ids.contains(detail.task.id) { app.discardDetail() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in today = Date() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in today = Date() }
        .sheet(item: $listEditor) { list in
            ListNameForm(list: list, lists: store.lists) { updated in
                if store.saveList(updated) { select(updated); listEditor = nil }
            }
        }
        .alert("删除列表？", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }), presenting: pendingRemoval) { list in
            Button("取消", role: .cancel) {}
            Button("删除列表", role: .destructive) {
                if store.removeList(list.id), selectedList == list.id { selectedList = nil; scope = .all }
            }
        } message: { list in Text("“\(list.name)”里的任务会保留在“全部”中。") }
    }
    private func select(_ list: TaskList) {
        selectedList = list.id; scope = .all; query = ""; completedExpanded = true
    }
    private func sidebarButton(_ name: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Image(systemName: icon).foregroundStyle(.teal).frame(width: 20); Text(name).lineLimit(1); Spacer() }
                .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 40).contentShape(Rectangle())
                .background(selected && query.isEmpty ? Color.primary.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(SurfaceButtonStyle())
    }
    private func taskRow(_ task: Todo) -> some View {
        let burst = bursts.first { $0.taskID == task.id }
        return TaskRow(burst: burst, onCompletionChange: completionChanged, task: task, app: app)
            .zIndex(burst == nil ? 0 : 1)
    }
    private func completionChanged(_ id: UUID, _ completed: Bool) {
        bursts.removeAll { $0.taskID == id }
        guard completed else { return }
        if let sound = CompletionBurst.sound {
            sound.stop()
            sound.volume = 0.65
            sound.play()
        }
        let burst = CompletionBurst(taskID: id)
        bursts.append(burst)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(CompletionBurst.duration))
            bursts.removeAll { $0.id == burst.id }
        }
    }
}

private struct TaskComposer: View {
    let scope: Scope
    let listID: UUID?
    let app: Controller
    let didAdd: () -> Void
    @AppStorage private var title: String
    @AppStorage private var draftImportant: Bool
    @FocusState private var adding: Bool

    init(scope: Scope, listID: UUID?, app: Controller, didAdd: @escaping () -> Void) {
        self.scope = scope
        self.listID = listID
        self.app = app
        self.didAdd = didAdd
        let key = "composer." + (listID?.uuidString ?? scope.rawValue)
        _title = AppStorage(wrappedValue: "", key + ".title")
        _draftImportant = AppStorage(wrappedValue: scope == .important, key + ".important")
    }

    var body: some View {
        HStack {
            iconButton("plus", "输入新任务") { adding = true }
            TextField("添加任务", text: $title)
                .textFieldStyle(.plain)
                .focused($adding)
                .onSubmit(add)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { adding = true })
            iconButton(draftImportant ? "star.fill" : "star", draftImportant ? "取消重要标记" : "标为重要任务") { draftImportant.toggle() }
                .foregroundStyle(draftImportant ? Color.orange : .secondary)
            iconButton("calendar.badge.plus", "设置截止日期和时间") { editDraft() }
            Button(action: add) {
                Text("添加").fontWeight(.semibold).frame(minWidth: 52, minHeight: 26)
            }.buttonStyle(.borderedProminent).tint(.teal).disabled(clean.isEmpty)
        }
        .padding(.horizontal, 6)
        .background {
            RoundedRectangle(cornerRadius: 9)
                .fill(.regularMaterial)
                .contentShape(Rectangle())
                .onTapGesture { adding = true }
                .accessibilityHidden(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: Controller.newTaskRequested)) { _ in editDraft() }
    }
    private var clean: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var draft: Todo {
        var task = Todo(title: clean, important: draftImportant, day: scope == .today ? Date() : nil, listID: listID)
        if scope == .planned { task.setDueDay(offset: 0) }
        return task
    }
    private func editDraft() { app.edit(draft, onSave: clearComposer) }
    private func add() {
        guard !clean.isEmpty, app.store.save(draft) else { return }
        clearComposer()
    }
    private func clearComposer() {
        title = ""
        draftImportant = scope == .important
        didAdd()
    }
}

private struct TaskInspector: View {
    @ObservedObject var detail: DetailDraft
    let app: Controller
    let completionChanged: (UUID, Bool) -> Void
    @State private var confirmDelete = false
    @State private var choosingDate = false

    var body: some View {
        let current = app.store.items.first { $0.id == detail.task.id }
        let inMyDay = detail.task.inMyDay(on: Date())
        let changed = detail.task != detail.original
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 8) {
                        if let current {
                            Button {
                                if let done = app.store.toggleCompletion(id: current.id) {
                                    completionChanged(current.id, done)
                                }
                            } label: {
                                Image(systemName: current.completed ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(current.completed ? Color.green : .secondary)
                                    .font(.system(size: 18)).frame(width: 28, height: 38)
                            }.accessibilityLabel(current.completed ? "标记为未完成" : "标记为已完成")
                        }
                        TextField("任务名称", text: $detail.task.title, axis: .vertical)
                            .font(.system(size: 17, weight: .semibold)).lineLimit(1...5)
                            .textFieldStyle(.plain).frame(maxWidth: .infinity, alignment: .leading)
                        Button { detail.task.important.toggle() } label: {
                            Image(systemName: detail.task.important ? "star.fill" : "star")
                                .foregroundStyle(detail.task.important ? Color.orange : .secondary)
                                .frame(width: 32, height: 38)
                        }.accessibilityLabel(detail.task.important ? "取消重要" : "标为重要")
                    }.padding(.vertical, 13)
                    Divider()
                    Button { detail.task.setMyDay(!inMyDay) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "sun.max").frame(width: 20)
                            Text(inMyDay ? "已加入我的一天" : "加入我的一天")
                            Spacer()
                            Image(systemName: inMyDay ? "minus" : "plus").font(.caption)
                        }.foregroundStyle(inMyDay ? Color.teal : .secondary)
                            .frame(minHeight: 48).contentShape(Rectangle())
                    }
                    Divider()
                    Button { choosingDate.toggle() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "calendar").frame(width: 20)
                            if let due = detail.task.due {
                                Text(due, format: .dateTime.year().month().day().hour().minute())
                            } else { Text("添加截止时间") }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption2)
                        }.foregroundStyle(.secondary).frame(minHeight: 48).contentShape(Rectangle())
                    }.popover(isPresented: $choosingDate) {
                        DueOptions(task: $detail.task).buttonStyle(.automatic).padding(14).frame(width: 260)
                    }
                    Divider()
                    TextField("添加备注", text: $detail.task.note, axis: .vertical)
                        .textFieldStyle(.plain).lineLimit(3...16).padding(.vertical, 16)
                }.buttonStyle(.plain).padding(.horizontal, 16)
            }
            Divider()
            HStack(spacing: 4) {
                iconButton("sidebar.right", "收起详情", app.closeDetail)
                Spacer()
                if changed || !detail.existing {
                    Button("取消", action: app.discardDetail)
                    Button(detail.existing ? "保存" : "添加") { app.saveDetail() }
                        .buttonStyle(.borderedProminent).tint(.teal)
                        .disabled(detail.task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else if let time = current?.completedAt {
                    Text("完成于 \(time.formatted(.dateTime.month().day().hour().minute()))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if detail.existing {
                    iconButton("trash", "删除任务") { confirmDelete = true }
                }
            }.padding(.horizontal, 4).frame(minHeight: 46)
        }
        .padding(.top, windowDragStripHeight)
        .background(Color(nsColor: .textBackgroundColor))
        .alert("删除这项任务？", isPresented: $confirmDelete) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if app.store.change({ $0.removeAll { $0.id == detail.task.id } }) { app.discardDetail() }
            }
        }
    }
}

struct DueOptions: View {
    @Binding var task: Todo
    @State private var suggested = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date()
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("截止时间", systemImage: "calendar.badge.clock").font(.headline)
                Spacer()
                if task.due != nil {
                    Button("清除") { task.due = nil }.buttonStyle(.link)
                } else { Text("未设置").font(.caption).foregroundStyle(.secondary) }
            }
            HStack {
                Button("今天") { task.setDueDay(offset: 0) }
                Button("明天") { task.setDueDay(offset: 1) }
                if task.due == nil {
                    Button("自选日期和时间") { task.due = suggested }
                }
            }.controlSize(.regular)
            HStack {
                    DatePicker("截止日期和时间", selection: Binding(get: { task.due ?? suggested }, set: { task.due = $0 }),
                               displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.field).labelsHidden()
                        .opacity(task.due == nil ? 0.65 : 1)
            }.frame(height: 28)
        }
    }
}

private struct ListNameForm: View {
    @State var list: TaskList
    let lists: [TaskList]
    let save: (TaskList) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let name = list.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let duplicate = lists.contains { $0.id != list.id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
        VStack(alignment: .leading, spacing: 14) {
            Text(lists.contains { $0.id == list.id } ? "重命名列表" : "新建列表").font(.headline)
            TextField("列表名称", text: $list.name).textFieldStyle(.roundedBorder)
            if duplicate { Text("已有同名列表").font(.caption).foregroundStyle(.secondary) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { list.name = name; save(list) }.keyboardShortcut(.defaultAction).disabled(name.isEmpty || duplicate)
            }
        }.padding(18).frame(width: 280)
    }
}
