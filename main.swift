import SwiftUI
import AppKit

final class DetailDraft: ObservableObject {
    let original: Todo
    @Published var task: Todo
    let existing: Bool
    let onSave: () -> Void

    init(_ task: Todo, existing: Bool, onSave: @escaping () -> Void) {
        original = task
        self.task = task
        self.existing = existing
        self.onSave = onSave
    }
}

@MainActor final class Controller: NSObject, NSApplicationDelegate, ObservableObject {
    let store = Store(file: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("DesktopTodo/tasks.json"))
    let background = BackgroundSettings()
    let reminders = ReminderService()
    let updates = UpdateService()
    lazy var quickEntry = QuickEntry(store: store)
    var board: NSWindow?
    @Published private(set) var detail: DetailDraft?
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in updates.start() }
        reminders.start()
        reminders.onOpen = { [weak self] id in
            guard let self else { return }
            self.openBoard()
            if let task = self.store.items.first(where: { $0.id == id }) { self.edit(task) }
        }
        store.didPersist = { [weak self] items in self?.reminders.synchronize(items) }
        reminders.synchronize(store.items)
        let menu = NSMenu()
        let appItem = menu.addItem(withTitle: "ToDoy", action: nil, keyEquivalent: "")
        let commands = NSMenu()
        for (name, action, key) in [("展开任务窗口", #selector(openBoard), "1"), ("新建任务", #selector(newTask), "n")] {
            commands.addItem(withTitle: name, action: action, keyEquivalent: key).target = self
        }
        commands.addItem(.separator())
        commands.addItem(withTitle: "退出ToDoy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = commands
        let editMenu = NSMenu(title: "编辑")
        for (name, action, key) in [("撤销","undo:","z"),("剪切","cut:","x"),("复制","copy:","c"),("粘贴","paste:","v"),("全选","selectAll:","a")] {
            editMenu.addItem(withTitle: name, action: Selector(action), keyEquivalent: key)
        }
        menu.addItem(withTitle: "编辑", action: nil, keyEquivalent: "").submenu = editMenu
        NSApp.mainMenu = menu
    }
    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        openBoard()
        return true
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        reminders.synchronize(store.items)
        Task { @MainActor in updates.checkAutomatically() }
    }
    @MainActor func installUpdate() {
        guard canLeaveDetail(), quickEntry.prepareForUpdate() else { return }
        if updates.install() { NSApp.terminate(nil) }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            await reminders.finishPendingUpdates()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first, url.scheme == "local-desktop-todo" else { return }
        if url.host == "new" {
            quickEntry.show(at: NSEvent.mouseLocation)
            return
        }
        openBoard()
        DispatchQueue.main.async {
            if url.host == "task", let id = UUID(uuidString: url.lastPathComponent),
               let task = self.store.items.first(where: { $0.id == id }) { self.edit(task) }
        }
    }
    func host<V: View>(_ view: V) -> NSView { NSHostingView(rootView: view.environment(\.locale, Locale(identifier: "zh_CN"))) }
    static let newTaskRequested = Notification.Name("ToDoy.newTaskRequested")
    @objc func newTask() {
        if let board, board.isKeyWindow {
            guard board.attachedSheet == nil else { return }
            NotificationCenter.default.post(name: Self.newTaskRequested, object: nil)
        } else if quickEntry.isKeyWindow { return }
        else { edit(Todo(day: Date())) }
    }
    @objc func openBoard() {
        if board == nil {
            let w = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 930,height: 570), styleMask: [.titled,.closable,.resizable,.miniaturizable,.fullSizeContentView], backing: .buffered, defer: false)
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.titlebarSeparatorStyle = .none
            w.title = "ToDoy"; w.isReleasedWhenClosed = false
            w.contentView = host(Board(store: store, app: self, background: background, updates: updates)); w.center(); w.setFrameAutosaveName("DesktopTodoBoard")
            board = w
        }
        board?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func edit(_ task: Todo, onSave: @escaping () -> Void = {}) {
        if detail?.task.id == task.id { return }
        guard canLeaveDetail() else { return }
        if board?.isVisible != true { openBoard() }
        detail = DetailDraft(task, existing: store.items.contains { $0.id == task.id }, onSave: onSave)
    }
    func canLeaveDetail() -> Bool {
        guard let detail, detail.task != detail.original else { return true }
        let alert = NSAlert()
        alert.messageText = "保存对任务的修改？"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "继续编辑")
        alert.addButton(withTitle: "放弃修改")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return saveDetail()
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }
    func closeDetail() {
        if canLeaveDetail() { detail = nil }
    }
    func discardDetail() { detail = nil }
    func toggleCompletion(id: UUID) -> Bool? {
        if let detail, detail.task.id == id, detail.task != detail.original {
            guard saveDetail() else { return nil }
        }
        return store.toggleCompletion(id: id)
    }
    @discardableResult func saveDetail() -> Bool {
        guard let detail else { return true }
        let draft = detail.task
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { NSSound.beep(); return false }
        if let reminder = draft.reminderAt, reminder <= Date(),
           !detail.existing || draft.reminderAt != detail.original.reminderAt {
            let alert = NSAlert()
            alert.messageText = "提醒时间已过"
            alert.informativeText = "请选择未来的提醒时间，或清除这次提醒。"
            alert.runModal()
            return false
        }
        var updated = draft
        if detail.existing {
            guard let latest = store.items.first(where: { $0.id == draft.id }) else { return false }
            updated = latest
            let original = detail.original
            if original.title != draft.title { updated.title = title }
            if original.note != draft.note { updated.note = draft.note }
            if original.important != draft.important { updated.important = draft.important }
            if original.due != draft.due { updated.due = draft.due }
            if original.reminderAt != draft.reminderAt { updated.reminderAt = draft.reminderAt }
            if original.recurrence != draft.recurrence { updated.recurrence = draft.recurrence }
            if original.day != draft.day || original.excludedFromMyDay != draft.excludedFromMyDay {
                updated.day = draft.day; updated.excludedFromMyDay = draft.excludedFromMyDay
            }
        } else { updated.title = title }
        guard store.save(updated) else { return false }
        detail.onSave()
        self.detail = nil
        return true
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openBoard(); return true
    }
}

if CommandLine.arguments.contains("--self-check") {
    try runScheduleChecks()
    try runUpdateChecks()
    let calendar = Calendar.current
    let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 12))!
    let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
    var overdue = Todo(title: "逾期任务", due: yesterday)
    precondition(Scope.overdue.shows(overdue, now: today))
    precondition(Scope.today.shows(overdue, now: today) && overdue.isOverdue(on: today))
    overdue.setMyDay(false, on: today)
    precondition(Scope.overdue.shows(overdue, now: today))
    precondition(!Scope.today.shows(overdue, now: today))
    precondition(Scope.today.shows(overdue, now: tomorrow))
    overdue.excludedFromMyDay = nil
    overdue.completed = true
    overdue.completedAt = today
    precondition(!Scope.overdue.shows(overdue, now: today))
    precondition(Scope.today.shows(overdue, now: today) && !overdue.isOverdue(on: today))
    precondition(!Scope.today.shows(overdue, now: tomorrow))
    var future = Todo(title: "延期任务", due: tomorrow)
    precondition(!Scope.overdue.shows(future, now: today))
    precondition(!Scope.today.shows(future, now: today) && !future.isOverdue(on: today))
    future.setMyDay(true, on: today)
    precondition(Scope.today.shows(future, now: today))
    let dueNow = Todo(title: "今天到期", due: today)
    precondition(!Scope.overdue.shows(dueNow, now: today))
    precondition(Scope.overdue.shows(dueNow, now: today.addingTimeInterval(1)))
    precondition(!Scope.overdue.shows(Todo(title: "无截止时间"), now: today))
    precondition(Scope.today.shows(dueNow, now: today) && !dueNow.isOverdue(on: today))
    precondition(dueNow.isOverdue(on: today.addingTimeInterval(1)))
    precondition(!Scope.today.shows(Todo(title: "未安排"), now: today))
    let cases: [(Todo, [Scope])] = [
        (Todo(title: "无日期"), [.all]),
        (Todo(title: "将来到期", due: tomorrow), [.planned, .all]),
        (Todo(title: "恰好到期", due: today), [.today, .planned, .all]),
        (Todo(title: "今天已逾期", due: today.addingTimeInterval(-1)), [.today, .overdue, .all]),
        (Todo(title: "昨日逾期", due: yesterday), [.today, .overdue, .all]),
        (Todo(title: "逾期重要", due: yesterday, important: true), [.today, .important, .overdue, .all]),
        (Todo(title: "手动加入", due: tomorrow, day: today), [.today, .planned, .all]),
        (Todo(title: "今天移出", due: yesterday, excludedFromMyDay: today), [.overdue, .all]),
        (Todo(title: "今天完成", due: yesterday, completedAt: today, completed: true), [.today, .planned, .all, .done]),
        (Todo(title: "历史完成", due: yesterday, completedAt: yesterday, completed: true), [.planned, .all, .done])
    ]
    for (item, expected) in cases {
        for scope in Scope.allCases {
            precondition(scope.shows(item, now: today) == expected.contains(scope), "\(item.title): \(scope.rawValue)")
        }
    }
    precondition(!Scope.planned.shows(dueNow, now: today.addingTimeInterval(1)))
    print("My Day overdue, completion, exclusion and rescheduling checks OK")
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("tasks.json")
    let store = Store(file: file)
    var task = Todo(title: "测试", due: Date(), day: Date())
    precondition(store.save(task))
    task.title = "已编辑"; task.important = true
    precondition(store.save(task))
    precondition(Store(file: file).items == [task] && Scope.today.shows(task, now: Date()))
    task.completed = true
    precondition(store.save(task) && Scope.done.shows(task, now: Date()))
    let saved = Store(file: file).items[0]
    precondition([Scope.today, .important, .planned, .all, .done].allSatisfy { $0.shows(saved, now: Date()) })
    precondition(!Scope.overdue.shows(saved, now: Date()))
    task.completed = false
    precondition(store.save(task) && !Scope.done.shows(task, now: Date()) && Scope.today.shows(task, now: Date()))
    for expected in [true, false, true, false] {
        precondition(store.toggleCompletion(id: task.id) == expected)
        let restored = Store(file: file).items[0]
        precondition(restored.completed == expected && (restored.completedAt != nil) == expected)
    }
    precondition(store.change { $0.removeAll() } && Store(file: file).items.isEmpty)
    var lifecycle = Todo(title: "分类切换", due: tomorrow)
    func checkClassification(planned: Bool, overdue: Bool, done: Bool) {
        let items = Store(file: file).items
        precondition(items.contains { Scope.planned.shows($0, now: today) } == planned)
        precondition(items.contains { Scope.overdue.shows($0, now: today) } == overdue)
        precondition(items.contains { $0.isOverdue(on: today) } == overdue, "红点与逾期分类一致")
        precondition(items.contains { Scope.done.shows($0, now: today) } == done)
    }
    precondition(store.save(lifecycle))
    checkClassification(planned: true, overdue: false, done: false)
    lifecycle.due = yesterday
    precondition(store.save(lifecycle))
    checkClassification(planned: false, overdue: true, done: false)
    precondition(store.toggleCompletion(id: lifecycle.id) == true)
    checkClassification(planned: true, overdue: false, done: true)
    precondition(store.toggleCompletion(id: lifecycle.id) == false)
    checkClassification(planned: false, overdue: true, done: false)
    lifecycle.due = tomorrow
    precondition(store.save(lifecycle))
    checkClassification(planned: true, overdue: false, done: false)
    lifecycle.due = nil
    precondition(store.save(lifecycle))
    checkClassification(planned: false, overdue: false, done: false)
    precondition(store.change { $0.removeAll() })
    checkClassification(planned: false, overdue: false, done: false)
    print("All scope classifications, transitions and overdue badge checks OK")
    print("CRUD and persistence OK")
} else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = Controller()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
