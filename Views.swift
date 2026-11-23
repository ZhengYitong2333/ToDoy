import SwiftUI

private struct SurfaceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.contentShape(Rectangle())
    }
}

private struct SidebarButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.68), value: configuration.isPressed)
    }
}

func iconButton(_ symbol: String, _ title: String, _ action: @escaping () -> Void) -> some View {
    Button(action: action) { Image(systemName: symbol).font(.system(size: 17, weight: .medium)).frame(width: 44, height: 44).contentShape(Rectangle()) }
        .buttonStyle(SurfaceButtonStyle()).accessibilityLabel(title).help(title)
}

struct TaskRow: View {
    let now: Date
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
                    Text(task.title).font(.system(size: 15)).lineLimit(1).strikethrough(task.completed)
                    if let completed = task.completedAt {
                        Text("完成于 \(completed.formatted(.dateTime.year().month().day().hour().minute()))")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if let due = task.due {
                        let overdue = task.isOverdue(on: now)
                        HStack(spacing: 4) {
                            if overdue { Text("已逾期") }
                            Text(due, format: .dateTime.year().month().day().hour().minute())
                        }.font(.caption).foregroundStyle(overdue ? Color.red : .secondary)
                    }
                    if !task.completed && (task.reminderAt != nil || task.recurrence != nil) {
                        HStack(spacing: 8) {
                            if let reminder = task.reminderAt {
                                Label(reminder.formatted(.dateTime.month().day().hour().minute()), systemImage: "bell")
                            }
                            if let rule = task.recurrence { Label(rule.title, systemImage: "repeat") }
                        }.font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
        if let done = app.toggleCompletion(id: task.id) { onCompletionChange(task.id, done) }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: Store
    @ObservedObject var app: Controller
    @ObservedObject var background: BackgroundSettings
    @ObservedObject var updates: UpdateService
    @State private var backgroundPreferences = false
    @State private var softwareUpdate = false
    @AppStorage("list.displayOptions") private var displayOptionsData = Data()
    @State private var scope = Scope.today
    @State private var selectedList: UUID?
    @State private var listEditor: TaskList?
    @State private var pendingRemoval: TaskList?
    @State private var query = ""
    @State private var hoveredSidebarItem: String?
    @FocusState private var composerFocused: Bool
    @State private var today = Date()
    @State private var completedExpanded = true
    @State private var bursts: [CompletionBurst] = []
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Label("ToDoy", systemImage: "checklist").font(.title3.bold())
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading).padding(.horizontal, 14)
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索任务", text: $query).textFieldStyle(.plain)
                }
                .padding(.horizontal, 10).frame(height: 28)
                .background(.background.opacity(0.8), in: Capsule())
                .overlay(Capsule().strokeBorder(.primary.opacity(0.08)))
                .padding(.horizontal, 12)
                .simultaneousGesture(TapGesture().onEnded { app.closeDetail() })
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Scope.allCases, id: \.self) { item in
                            sidebarButton(item.rawValue, id: "scope-\(item.rawValue)", icon: item.icon, color: sidebarColor(item), selected: selectedList == nil && scope == item,
                                          showsBadge: item == .overdue && store.items.contains { $0.isOverdue(on: today) }) {
                                today = Date()
                                selectedList = nil; scope = item; query = ""; completedExpanded = true
                            }
                        }
                        Divider().padding(.horizontal, 12).padding(.vertical, 8)
                        ForEach(store.lists) { list in
                            sidebarButton(list.name, id: "list-\(list.id.uuidString)", icon: "list.bullet", selected: selectedList == list.id) { select(list) }
                                .contextMenu {
                                    Button("重命名列表…") { listEditor = list }
                                    Button("删除列表…", role: .destructive) { pendingRemoval = list }
                                }
                        }
                    }
                }
                .background { outsideDetailTapArea }
                Button {
                    guard app.canLeaveDetail() else { return }
                    app.discardDetail()
                    listEditor = TaskList(name: "")
                } label: {
                    Label("新建列表", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                }.buttonStyle(SurfaceButtonStyle()).padding(.horizontal, 14)
            }.padding(.vertical, 10).padding(.top, windowDragStripHeight).frame(width: 180)
                .background { outsideDetailTapArea.background(.regularMaterial) }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Text(query.isEmpty ? (store.lists.first { $0.id == selectedList }?.name ?? scope.rawValue) : "搜索结果").font(.system(size: 32, weight: .bold))
                    Spacer()
                    Menu {
                        Menu {
                            Picker("排序方式", selection: Binding(get: { displayOptions.sort }, set: { value in
                                var options = displayOptions; options.sort = value; saveDisplayOptions(options)
                            })) {
                                ForEach(TaskSort.allCases, id: \.self) { order in
                                    Label(order.rawValue, systemImage: order.icon).tag(order)
                                }
                            }.pickerStyle(.inline)
                        } label: { Label("排序", systemImage: "arrow.up.arrow.down") }
                        Divider()
                        Button("更改背景…", systemImage: "photo") { backgroundPreferences = true }
                        Button(updates.hasUpdate ? "软件更新 · 有新版本" : "软件更新…", systemImage: "arrow.down.circle") {
                            softwareUpdate = true
                            updates.check()
                        }
                        if (scope != .done && scope != .overdue) || selectedList != nil || !query.isEmpty {
                            Button(displayOptions.hideCompleted ? "显示已完成任务" : "隐藏已完成任务",
                                   systemImage: displayOptions.hideCompleted ? "eye" : "eye.slash") {
                                var options = displayOptions
                                options.hideCompleted.toggle()
                                saveDisplayOptions(options)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 18, weight: .semibold))
                            .frame(width: 36, height: 30)
                            .background(.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(alignment: .topTrailing) {
                                if updates.hasUpdate {
                                    Circle().fill(.red).frame(width: 8, height: 8)
                                        .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1.5))
                                        .offset(x: 2, y: -2).allowsHitTesting(false)
                                }
                            }
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .accessibilityLabel(updates.hasUpdate ? "设置，有新版本可更新" : "设置")
                }
                HStack {
                    Text(today, format: .dateTime.month().day().weekday(.wide))
                    Spacer()
                    if displayOptions.sort != .defaultOrder {
                        Label(displayOptions.sort.rawValue, systemImage: displayOptions.sort.icon)
                    }
                }.font(.caption).foregroundStyle(.white.opacity(0.85))
                ScrollView { VStack(spacing: 5) {
                    let celebrating = Set(bursts.map(\.taskID))
                    let rows = store.items.filter { task in
                        if !query.isEmpty { return task.title.localizedCaseInsensitiveContains(query) || task.note.localizedCaseInsensitiveContains(query) }
                        if let selectedList { return task.listID == selectedList }
                        // Finish the celebration before removing a completed overdue task.
                        if scope == .overdue, celebrating.contains(task.id), let due = task.due, due < today { return true }
                        return scope.shows(task, now: today)
                    }
                    let allCompleted = rows.filter { $0.completed && !celebrating.contains($0.id) }
                    let hideCompleted = displayOptions.hideCompleted && (scope != .done || selectedList != nil || !query.isEmpty)
                    let completed = hideCompleted ? [] : displayOptions.sort.arrange(allCompleted, completed: true)
                    let pending = displayOptions.sort.arrange(rows.filter { !$0.completed || celebrating.contains($0.id) })
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
                    if hideCompleted && !allCompleted.isEmpty {
                        Button {
                            var options = displayOptions; options.hideCompleted = false; saveDisplayOptions(options)
                        } label: {
                            Label("显示已完成任务（\(allCompleted.count)）", systemImage: "eye")
                                .font(.caption).foregroundStyle(.white.opacity(0.8))
                                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                        }.buttonStyle(.plain)
                    }
                    if rows.isEmpty {
                        Text(!query.isEmpty ? "没有匹配的任务" : (scope == .overdue && selectedList == nil ? "暂无逾期任务" : "暂无任务"))
                            .padding(.top, 28).foregroundStyle(.white)
                    }
                } }
                .background { outsideDetailTapArea }
                .id(selectedList?.uuidString ?? scope.rawValue)
                TaskComposer(scope: scope, listID: selectedList, app: app, adding: $composerFocused) {
                    query = ""
                    if scope == .done || scope == .overdue { scope = .all }
                }.id(selectedList?.uuidString ?? scope.rawValue)
            }.padding(24).padding(.top, windowDragStripHeight)
            .background {
                TaskBackground(settings: background)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: app.closeDetail)
            }
            .environment(\.colorScheme, .dark)
            if let detail = app.detail {
                HStack(spacing: 0) {
                    Divider()
                    TaskInspector(detail: detail, app: app, completionChanged: completionChanged)
                        .id(detail.task.id)
                        .frame(width: 300)
                }
                .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: app.detail != nil)
        .clipped()
        .overlay(alignment: .top) {
            Color.clear.frame(height: windowDragStripHeight)
                .contentShape(Rectangle()).gesture(WindowDragGesture()).accessibilityHidden(true)
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 680, minHeight: 420)
        .onKeyPress(.return) {
            guard !composerFocused else { return .ignored }
            composerFocused = true
            return .handled
        }
        .onChange(of: store.items) { _, items in
            today = Date()
            if let detail = app.detail, detail.existing, !items.contains(where: { $0.id == detail.task.id }) { app.discardDetail() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in today = Date() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in today = Date() }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { today = $0 }
        .sheet(isPresented: $backgroundPreferences) { BackgroundPreferences(settings: background) }
        .sheet(isPresented: $softwareUpdate) {
            SoftwareUpdateView(updates: updates, install: app.installUpdate)
        }
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
    // Background hit areas leave task buttons free to open or switch the inspector.
    private var outsideDetailTapArea: some View {
        Color.clear.contentShape(Rectangle()).onTapGesture(perform: app.closeDetail)
    }
    private var displayKey: String { selectedList?.uuidString ?? scope.rawValue }
    private var displayOptions: ListDisplayOptions {
        let all = (try? JSONDecoder().decode([String: ListDisplayOptions].self, from: displayOptionsData)) ?? [:]
        var options = all[displayKey] ?? ListDisplayOptions()
        if options.sort == .defaultOrder { options.sort = .due }
        return options
    }
    private func saveDisplayOptions(_ options: ListDisplayOptions) {
        var all = (try? JSONDecoder().decode([String: ListDisplayOptions].self, from: displayOptionsData)) ?? [:]
        all[displayKey] = options
        if let data = try? JSONEncoder().encode(all) { displayOptionsData = data }
    }
    private func select(_ list: TaskList) {
        selectedList = list.id; scope = .all; query = ""; completedExpanded = true
    }
    private func sidebarColor(_ scope: Scope) -> Color {
        switch scope {
        case .today: return .indigo
        case .important: return .orange
        case .planned: return .teal
        case .overdue: return .red
        case .all: return .blue
        case .done: return .green
        }
    }
    private func sidebarButton(_ name: String, id: String, icon: String, color: Color = .secondary, selected: Bool, showsBadge: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            guard app.canLeaveDetail() else { return }
            app.discardDetail()
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(color).frame(width: 20)
                Text(name).lineLimit(1)
                Spacer()
                if showsBadge {
                    Circle().fill(.red).frame(width: 7, height: 7).accessibilityHidden(true)
                }
            }
                .padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 32).contentShape(Rectangle())
                .background {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(selected && query.isEmpty
                              ? Color.primary.opacity(0.10)
                              : hoveredSidebarItem == id ? Color.primary.opacity(0.055) : .clear)
                }
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.14)) {
                        hoveredSidebarItem = hovering ? id : (hoveredSidebarItem == id ? nil : hoveredSidebarItem)
                    }
                }
        }.buttonStyle(SidebarButtonStyle())
            .accessibilityAddTraits(selected && query.isEmpty ? .isSelected : [])
            .accessibilityValue(showsBadge ? "有逾期未完成任务" : "")
    }
    private func taskRow(_ task: Todo) -> some View {
        let burst = bursts.first { $0.taskID == task.id }
        return TaskRow(now: today, burst: burst, onCompletionChange: completionChanged, task: task, app: app)
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
    @FocusState.Binding private var adding: Bool

    init(scope: Scope, listID: UUID?, app: Controller, adding: FocusState<Bool>.Binding, didAdd: @escaping () -> Void) {
        self.scope = scope
        self.listID = listID
        self.app = app
        self._adding = adding
        self.didAdd = didAdd
        let key = "composer." + (listID?.uuidString ?? scope.rawValue)
        _title = AppStorage(wrappedValue: "", key + ".title")
        _draftImportant = AppStorage(wrappedValue: scope == .important, key + ".important")
    }

    var body: some View {
        HStack {
            iconButton("plus", "输入新任务", focusInput)
            TextField("添加任务", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($adding)
                .onSubmit(add)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { _ in focusInput() })
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
                .onTapGesture(perform: focusInput)
                .accessibilityHidden(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: Controller.newTaskRequested)) { _ in editDraft() }
    }
    private var clean: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private func focusInput() {
        guard app.canLeaveDetail() else { return }
        app.discardDetail()
        adding = true
    }
    private var draft: Todo {
        var task = Todo(title: clean, important: draftImportant, day: scope == .today ? Date() : nil, listID: listID)
        if scope == .planned {
            task.setDueDay(offset: 0)
            if task.isOverdue(on: Date()) { task.setDueDay(offset: 1) }
        }
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
    @State private var choosingReminder = false
    @State private var choosingRepeat = false

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
                                if let done = app.toggleCompletion(id: current.id) {
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
                    InspectorScheduleRow(icon: "bell", title: detail.task.reminderAt.map { $0.formatted(.dateTime.month().day().hour().minute()) } ?? "提醒我",
                                         color: detail.task.reminderAt == nil ? .secondary : .teal,
                                         action: { choosingReminder = true },
                                         clear: detail.task.reminderAt == nil ? nil : { detail.task.reminderAt = nil })
                        .disabled(current?.completed == true)
                        .popover(isPresented: $choosingReminder) {
                            ReminderOptions(date: $detail.task.reminderAt, service: app.reminders) { choosingReminder = false }
                        }
                    ReminderStatus(service: app.reminders)
                    InspectorScheduleRow(icon: "calendar", title: detail.task.due.map { $0.formatted(.dateTime.month().day().hour().minute()) } ?? "添加截止日期",
                                         color: detail.task.isOverdue(on: Date()) ? .red : (detail.task.due == nil ? .secondary : .teal),
                                         action: { choosingDate = true },
                                         clear: detail.task.due == nil ? nil : { detail.task.due = nil })
                        .popover(isPresented: $choosingDate) {
                            DueOptions(task: $detail.task) { choosingDate = false }
                        }
                    InspectorScheduleRow(icon: "repeat", title: detail.task.recurrence?.title ?? "重复",
                                         color: detail.task.recurrence == nil ? .secondary : .teal,
                                         action: { choosingRepeat = true },
                                         clear: detail.task.recurrence == nil ? nil : { detail.task.recurrence = nil })
                        .disabled(current?.completed == true)
                        .popover(isPresented: $choosingRepeat) {
                            RecurrenceOptions(task: $detail.task) { choosingRepeat = false }
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
    let close: () -> Void
    var body: some View { DeadlineOptions(task: $task, close: close) }
}

struct DateTimeOptions: View {
    @Binding var date: Date?
    var isReminder = false
    var authorize: (() async -> Bool)?
    let close: () -> Void
    @State private var selection: Date
    @State private var saving = false
    @State private var error: String?
    @State private var visible = true

    init(date: Binding<Date?>, isReminder: Bool = false, authorize: (() async -> Bool)? = nil, close: @escaping () -> Void) {
        _date = date
        self.isReminder = isReminder
        self.authorize = authorize
        self.close = close
        let now = Date()
        let calendar = Calendar.current
        let evening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now) ?? now
        let suggested = evening > now ? evening : (calendar.date(byAdding: .day, value: 1, to: evening) ?? evening)
        _selection = State(initialValue: date.wrappedValue ?? (isReminder ? now.addingTimeInterval(3600) : suggested))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(isReminder ? "提醒我" : "截止时间").font(.system(size: 16, weight: .semibold))
                Text(selection, format: .dateTime.month().day().weekday(.wide).hour().minute())
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            DatePicker(isReminder ? "提醒日期" : "截止日期", selection: $selection, displayedComponents: .date)
                .datePickerStyle(.graphical).labelsHidden()
                // The native macOS calendar has a fixed, compact intrinsic size.
                .fixedSize().scaleEffect(1.65)
                .frame(maxWidth: .infinity).frame(height: 250)
                .padding(8)
                .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Label("时间", systemImage: "clock").foregroundStyle(.secondary)
                Spacer()
                DatePicker(isReminder ? "提醒时间" : "截止时间", selection: $selection, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.field).labelsHidden().controlSize(.large)
            }
            if selection < Date() {
                Label(isReminder ? "请选择未来的提醒时间" : "此时间已过，未完成任务将显示为已逾期", systemImage: "clock.badge.exclamationmark")
                    .font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            Divider()
            HStack {
                if date != nil {
                    Button("清除") { date = nil; close() }.foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消", action: close).keyboardShortcut(.cancelAction).buttonStyle(.bordered)
                Button(saving ? "正在开启…" : "确定", action: confirm)
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(isReminder && selection <= Date())
            }.controlSize(.large)
        }
        .padding(16).frame(width: 320).buttonStyle(.plain).tint(.teal).disabled(saving)
        .onAppear { visible = true }
        .onDisappear { visible = false }
    }

    private func confirm() {
        let selected = Calendar.current.dateInterval(of: .minute, for: selection)?.start ?? selection
        guard !isReminder || selected > Date() else { error = "请选择未来的提醒时间"; return }
        saving = true
        Task { @MainActor in
            defer { saving = false }
            if let authorize, !(await authorize()) {
                error = "请在系统设置 → 通知中允许 ToDoy 发送通知。"
                return
            }
            guard visible else { return }
            guard !isReminder || selected > Date() else { error = "该时间已过，请重新选择"; return }
            date = selected
            close()
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
