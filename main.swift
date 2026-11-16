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

final class Controller: NSObject, NSApplicationDelegate, ObservableObject {
    let store = Store(file: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("DesktopTodo/tasks.json"))
    lazy var quickEntry = QuickEntry(store: store)
    var board: NSWindow?
    @Published private(set) var detail: DetailDraft?
    func applicationDidFinishLaunching(_ notification: Notification) {
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
            let w = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 930,height: 570), styleMask: [.titled,.closable,.resizable,.miniaturizable], backing: .buffered, defer: false)
            w.title = "ToDoy"; w.isReleasedWhenClosed = false
            w.contentView = host(Board(store: store, app: self)); w.center(); w.setFrameAutosaveName("DesktopTodoBoard")
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
    @discardableResult func saveDetail() -> Bool {
        guard let detail else { return true }
        let draft = detail.task
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { NSSound.beep(); return false }
        var updated = draft
        if detail.existing {
            guard let latest = store.items.first(where: { $0.id == draft.id }) else { return false }
            updated = latest
            let original = detail.original
            if original.title != draft.title { updated.title = title }
            if original.note != draft.note { updated.note = draft.note }
            if original.important != draft.important { updated.important = draft.important }
            if original.due != draft.due { updated.due = draft.due }
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
    precondition(Scope.allCases.allSatisfy { $0.shows(saved, now: Date()) })
    task.completed = false
    precondition(store.save(task) && !Scope.done.shows(task, now: Date()) && Scope.today.shows(task, now: Date()))
    for expected in [true, false, true, false] {
        precondition(store.toggleCompletion(id: task.id) == expected)
        let restored = Store(file: file).items[0]
        precondition(restored.completed == expected && (restored.completedAt != nil) == expected)
    }
    precondition(store.change { $0.removeAll() } && Store(file: file).items.isEmpty)
    print("CRUD and persistence OK")
} else {
    let app = NSApplication.shared
    let delegate = Controller()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
