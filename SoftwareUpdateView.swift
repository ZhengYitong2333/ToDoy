import SwiftUI

struct SoftwareUpdateView: View {
    @ObservedObject var updates: UpdateService
    let install: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var networkExpanded = false
    private let accent = Color(red: 0.08, green: 0.53, blue: 0.40)
    private var busy: Bool { updates.checking || updates.phase != nil }

    private var statusTitle: String {
        if let phase = updates.phase { return phase }
        if updates.checking { return "正在检查更新" }
        if updates.ready != nil { return "更新已准备就绪" }
        if let release = updates.available { return "新版本 \(release.version) 已发布" }
        if updates.error != nil { return "暂时无法检查更新" }
        return updates.lastChecked == nil ? "让 ToDoy 保持最新" : "你正在使用最新版本"
    }
    private var statusSubtitle: String {
        if let phase = updates.phase {
            return phase == "正在下载更新…" ? "下载将在后台进行，你可以继续使用 ToDoy。" : "更新处理中，任务与设置会保留。"
        }
        if updates.checking { return "正在获取最新的正式版本…" }
        if updates.ready != nil { return "安装后自动重启，任务与设置会保留。" }
        if updates.hasUpdate { return "升级 ToDoy，体验新的功能与改进。" }
        if updates.error != nil { return "请稍后重试，或检查下方的网络设置。" }
        if let checked = updates.lastChecked {
            return "上次检查 " + checked.formatted(date: .abbreviated, time: .shortened)
        }
        return "获取最新功能和问题修复。"
    }
    private var statusSymbol: String {
        if busy { return "arrow.triangle.2.circlepath" }
        if updates.ready != nil { return "checkmark.seal.fill" }
        if updates.hasUpdate { return "arrow.down.circle.fill" }
        return updates.error == nil ? "checkmark.circle.fill" : "wifi.exclamationmark"
    }

    var body: some View {
        VStack(spacing: 20) {
            header
            statusCard
            if let error = updates.error {
                Label {
                    Text(error).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                } icon: { Image(systemName: "exclamationmark.circle") }
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let release = updates.available { releaseNotes(release) }
            preferences
            footer
        }
        .padding(24).frame(width: 448)
        .background(.regularMaterial)
        .tint(accent)
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let icon = NSImage(named: "Todo") ?? NSImage(contentsOfFile: Bundle.main.path(forResource: "Todo", ofType: "icns") ?? "") {
                Image(nsImage: icon).resizable().frame(width: 48, height: 48)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("软件更新").font(.system(size: 19, weight: .semibold))
                Text("ToDoy · 当前版本 \(updates.currentVersion)")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(UpdateButtonStyle(accent: accent, compact: true))
            .keyboardShortcut(.cancelAction).accessibilityLabel("关闭软件更新").help("关闭")
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if busy { ProgressView().controlSize(.small).frame(width: 26, height: 26) }
                    else { Image(systemName: statusSymbol).font(.system(size: 25, weight: .medium)) }
                }.foregroundStyle(updates.error != nil && !updates.hasUpdate ? Color.orange : accent)
                VStack(alignment: .leading, spacing: 6) {
                    Text(statusTitle).font(.system(size: 16, weight: .semibold))
                    Text(statusSubtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if updates.phase == "正在下载更新…" {
                HStack(spacing: 10) {
                    ProgressView(value: updates.progress)
                    Text(updates.progress, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(18)
        .background(LinearGradient(colors: [accent.opacity(0.11), accent.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(accent.opacity(0.1), lineWidth: 1))
    }

    private func releaseNotes(_ release: AppRelease) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("本次更新").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            ScrollView {
                Text(.init(release.body ?? "包含功能改进与问题修复。"))
                    .font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 150)
        }
    }

    private var preferences: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.secondary).frame(width: 20)
                VStack(alignment: .leading, spacing: 4) {
                    Text("自动检查更新").font(.system(size: 13, weight: .medium))
                    Text("每小时检查，新版本以红点提示")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Toggle("自动检查更新", isOn: $updates.automatic).labelsHidden().toggleStyle(.switch).controlSize(.small)
            }.padding(14)
            Divider().padding(.horizontal, 14)
            VStack(alignment: .leading, spacing: 12) {
                Button { networkExpanded.toggle() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "network").frame(width: 20).foregroundStyle(.secondary)
                        Text("网络设置").font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text(updates.proxy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "跟随系统" : "自定义代理")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                            .rotationEffect(.degrees(networkExpanded ? 90 : 0)).foregroundStyle(.tertiary)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(busy)
                    .accessibilityLabel("网络设置，\(networkExpanded ? "已展开" : "已收起")")
                if networkExpanded {
                    TextField("代理地址，留空使用系统设置", text: $updates.proxy)
                        .textFieldStyle(.roundedBorder).font(.system(size: 12)).disabled(busy)
                    Text("支持 HTTP / SOCKS5，仅用于软件更新。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.padding(14)
        }
        .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.07), lineWidth: 1))
    }

    private var footer: some View {
        HStack {
            Link(destination: UpdateService.releasesURL) {
                HStack(spacing: 4) {
                    Text("版本记录")
                    Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .medium))
                }.font(.system(size: 12)).foregroundColor(.secondary)
            }
            Spacer()
            if updates.phase != nil {
                if updates.phase == "正在下载更新…" {
                    Button("取消下载", action: updates.cancelDownload).buttonStyle(UpdateButtonStyle(accent: accent))
                } else {
                    Text("请稍候…").font(.system(size: 12)).foregroundStyle(.secondary).frame(height: 34)
                }
            } else if updates.ready != nil {
                Button("安装并重启", action: install).buttonStyle(UpdateButtonStyle(accent: accent, prominent: true))
            } else if updates.hasUpdate {
                Button("下载更新", action: updates.download).buttonStyle(UpdateButtonStyle(accent: accent, prominent: true)).disabled(updates.checking)
            } else {
                Button(updates.checking ? "正在检查…" : "检查更新", action: updates.check)
                    .buttonStyle(UpdateButtonStyle(accent: accent, prominent: true)).disabled(updates.checking)
            }
        }
    }
}

private struct UpdateButtonStyle: ButtonStyle {
    let accent: Color
    var prominent = false
    var compact = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, compact ? 0 : 16).frame(height: compact ? 28 : 34)
            .foregroundStyle(prominent ? .white : Color.secondary)
            .background(prominent ? accent.opacity(hovered ? 0.88 : 1) : Color.primary.opacity(hovered ? 0.09 : 0.055), in: RoundedRectangle(cornerRadius: compact ? 14 : 9))
            .contentShape(Rectangle()).opacity(enabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
            .onHover { hovered = $0 }
    }
}
