import SwiftUI
import AppKit

private final class QuickDraft: ObservableObject {
    @Published var task = Todo()
}

private struct QuickForm: View {
    @ObservedObject var draft: QuickDraft
    let save: () -> Void
    let cancel: () -> Void
    @FocusState private var focused: Bool
    @State private var choosingDate = false

    var body: some View {
        HStack(spacing: 3) {
            TextField("添加任务…", text: $draft.task.title)
                .textFieldStyle(.plain).font(.system(size: 16, weight: .medium))
                .focused($focused).onSubmit(save)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { focused = true })
            Button { draft.task.important.toggle() } label: {
                Image(systemName: draft.task.important ? "star.fill" : "star")
                    .foregroundStyle(draft.task.important ? Color.orange : .secondary)
                    .frame(width: 29, height: 32).contentShape(Rectangle())
            }.accessibilityLabel(draft.task.important ? "取消重要" : "标为重要")
                .help(draft.task.important ? "取消重要" : "标为重要")
            Button { choosingDate.toggle() } label: {
                Image(systemName: draft.task.due == nil ? "calendar" : "calendar.badge.checkmark")
                    .foregroundStyle(draft.task.due == nil ? Color.secondary : .teal)
                    .frame(width: 29, height: 32).contentShape(Rectangle())
            }.accessibilityLabel("设置截止时间")
                .help(draft.task.due?.formatted() ?? "设置截止时间")
                .popover(isPresented: $choosingDate) {
                    DueOptions(task: $draft.task) { choosingDate = false }
                }
            Button(action: save) {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 24))
                    .frame(width: 32, height: 36).contentShape(Rectangle())
            }.accessibilityLabel("添加任务").help("添加任务（回车）")
                .foregroundStyle(draft.task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : .teal)
                .disabled(draft.task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.buttonStyle(.plain)
        .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 6).frame(width: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .onExitCommand { if choosingDate { choosingDate = false } else { cancel() } }
        .onAppear { focused = true }
    }
}

final class QuickEntry: NSPanel {
    private let store: Store
    private let draft = QuickDraft()
    override var canBecomeKey: Bool { true }

    init(store: Store) {
        self.store = store
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "快速添加任务"
        level = .floating
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
    }
    func show(at point: NSPoint) {
        let view = NSHostingView(rootView: QuickForm(draft: draft, save: { [weak self] in self?.save() },
                                                    cancel: { [weak self] in self?.dismissDraft() })
            .environment(\.locale, Locale(identifier: "zh_CN")))
        contentView = view
        setContentSize(view.fittingSize)
        guard let bounds = (NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main)?.visibleFrame else { return }
        let x = min(max(bounds.minX, point.x - 22), bounds.maxX - frame.width)
        let y = point.y - 12 - frame.height
        setFrameOrigin(NSPoint(x: x, y: y >= bounds.minY ? y : min(point.y + 12, bounds.maxY - frame.height)))
        makeKeyAndOrderFront(nil)
    }
    private func save() {
        var task = draft.task
        task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        task.day = Date()
        guard !task.title.isEmpty, store.save(task) else { return }
        dismissDraft()
    }
    private func dismissDraft() { orderOut(nil); draft.task = Todo() }

}
