import AppKit
import Combine
import UserNotifications

final class ReminderService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var message: String?
    var onOpen: ((UUID) -> Void)?
    private lazy var center = UNUserNotificationCenter.current()
    private var work: Task<Void, Never>?
    static let prefix = "todoy.task."

    func start() { center.delegate = self }
    func finishPendingUpdates() async { await work?.value }

    @MainActor func requestPermission() async -> Bool {
        do {
            let allowed = try await center.requestAuthorization(options: [.alert, .sound])
            message = allowed ? nil : "通知未开启，请在系统设置中允许 ToDoy 发送通知。"
            return allowed
        } catch {
            message = "无法启用通知：\(error.localizedDescription)"
            return false
        }
    }

    // Serialize reconciliations so a slow older update cannot restore a cancelled reminder.
    func synchronize(_ items: [Todo]) {
        let previous = work
        work = Task { @MainActor [weak self] in
            await previous?.value
            await self?.reconcile(items)
        }
    }

    static func requests(for items: [Todo], now: Date) -> [UNNotificationRequest] {
        items.compactMap { task in
            guard !task.completed, let time = task.reminderAt, time > now else { return nil }
            let content = UNMutableNotificationContent()
            content.title = "ToDoy · 提醒我"
            content.body = task.title
            content.sound = .default
            content.userInfo = ["taskID": task.id.uuidString]
            var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: time)
            components.timeZone = Calendar.current.timeZone
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            return UNNotificationRequest(identifier: prefix + task.id.uuidString, content: content, trigger: trigger)
        }
    }

    @MainActor private func reconcile(_ items: [Todo]) async {
        let requests = Self.requests(for: items, now: Date())
        let wanted = Set(requests.map(\.identifier))
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter {
            $0.hasPrefix(Self.prefix) && !wanted.contains($0)
        })
        let active = Set(items.filter { !$0.completed && $0.reminderAt != nil }.map { Self.prefix + $0.id.uuidString })
        let delivered = await center.deliveredNotifications()
        center.removeDeliveredNotifications(withIdentifiers: delivered.map { $0.request.identifier }.filter {
            $0.hasPrefix(Self.prefix) && !active.contains($0)
        })
        guard !requests.isEmpty else { message = nil; return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            message = "通知未开启，请在系统设置中允许 ToDoy 发送通知。"
            return
        }
        message = nil
        for request in requests {
            if let previous = pending.first(where: { $0.identifier == request.identifier }),
               previous.content.body == request.content.body,
               (previous.trigger as? UNCalendarNotificationTrigger)?.dateComponents == (request.trigger as? UNCalendarNotificationTrigger)?.dateComponents { continue }
            do { try await center.add(request) }
            catch { message = "提醒安排失败：\(error.localizedDescription)" }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let raw = response.notification.request.content.userInfo["taskID"] as? String, let id = UUID(uuidString: raw) {
            DispatchQueue.main.async { [weak self] in self?.onOpen?(id) }
        }
        completionHandler()
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
