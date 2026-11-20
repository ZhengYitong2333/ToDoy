import SwiftUI
import UniformTypeIdentifiers
import WidgetKit

struct Wallpaper: Identifiable {
    let id: String
    let name: String
    let category: String
    let file: String?
    let colors: [Color]
    static let all: [Wallpaper] = [
        .init(id: "gg-work", name: "工作G · 夜间专注", category: "GG和小屁", file: "gg-work", colors: []),
        .init(id: "gg-lunch", name: "干饭G · 公司食堂", category: "GG和小屁", file: "gg-lunch", colors: []),
        .init(id: "gg-cloud", name: "休息G · 雨夜咖啡馆", category: "GG和小屁", file: "gg-cloud", colors: []),
        .init(id: "gg-drone", name: "飞影穿梭 · 操控时刻", category: "GG和小屁", file: "gg-drone", colors: []),
        .init(id: "xp-snack", name: "零食管理员 · 补给站", category: "GG和小屁", file: "xp-snack", colors: []),
        .init(id: "xp-study", name: "工作屁 · 星空电脑桌", category: "GG和小屁", file: "xp-study", colors: []),
        .init(id: "xp-home", name: "等GG回家 · 窗边灯火", category: "GG和小屁", file: "xp-home", colors: []),
        .init(id: "xp-clean", name: "扫地Q · 今日清爽", category: "GG和小屁", file: "xp-clean", colors: []),
        .init(id: "duo-moonbay", name: "芜湖 · 月亮湾", category: "GG和小屁", file: "duo-moonbay", colors: []),
        .init(id: "duo-dumpling", name: "包饺子 · 人间烟火", category: "GG和小屁", file: "duo-dumpling", colors: []),
        .init(id: "duo-photo", name: "颐和园 · 给你拍照", category: "GG和小屁", file: "duo-photo", colors: []),
        .init(id: "duo-morning", name: "起床啦 · 云朵早晨", category: "GG和小屁", file: "duo-morning", colors: []),

        .init(id: "original", name: "流动色彩", category: "炫酷", file: "Landscape", colors: []),
        .init(id: "aurora", name: "极光", category: "炫酷", file: nil, colors: [.black, .indigo, .purple, .mint]),
        .init(id: "pastoral", name: "湖畔晨光", category: "田园", file: "pastoral", colors: []),
        .init(id: "meadow", name: "青野", category: "田园", file: nil, colors: [.init(red: 0.06, green: 0.22, blue: 0.18), .green, .yellow.opacity(0.5)]),
        .init(id: "mountain", name: "群山", category: "风景", file: "mountain", colors: []),
        .init(id: "anime", name: "海边列车", category: "动漫", file: "anime", colors: [.indigo, .pink]),
        .init(id: "cyber", name: "数字夜幕", category: "科技", file: nil, colors: [.black, .init(red: 0.02, green: 0.15, blue: 0.28), .cyan.opacity(0.6)]),
        .init(id: "plasma", name: "星际", category: "科技", file: nil, colors: [.black, .indigo, .blue]),
        .init(id: "cool-prism", name: "流光棱镜", category: "炫酷", file: "cool-prism", colors: []),
        .init(id: "cool-neon", name: "霓虹海浪", category: "炫酷", file: "cool-neon", colors: []),
        .init(id: "pastoral-garden", name: "雨后小院", category: "田园", file: "pastoral-garden", colors: []),
        .init(id: "pastoral-field", name: "晨光原野", category: "田园", file: "pastoral-field", colors: []),
        .init(id: "scenery-coast", name: "暮色海岸", category: "风景", file: "scenery-coast", colors: []),
        .init(id: "scenery-lake", name: "晨雾湖泊", category: "风景", file: "scenery-lake", colors: []),
        .init(id: "scenery-dunes", name: "月下沙丘", category: "风景", file: "scenery-dunes", colors: []),
        .init(id: "anime-rain", name: "雨夜街角", category: "动漫", file: "anime-rain", colors: []),
        .init(id: "anime-summer", name: "夏日坡道", category: "动漫", file: "anime-summer", colors: []),
        .init(id: "anime-stars", name: "星空观测站", category: "动漫", file: "anime-stars", colors: []),
        .init(id: "tech-circuit", name: "翡翠芯片", category: "科技", file: "tech-circuit", colors: []),
        .init(id: "tech-orbit", name: "轨道空间站", category: "科技", file: "tech-orbit", colors: [])
    ]
}

struct WallpaperSurface: View {
    let wallpaper: Wallpaper
    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let file = wallpaper.file, let image = NSImage(named: file) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: wallpaper.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    if wallpaper.category == "科技" {
                        Canvas { context, size in
                            for x in stride(from: 0.0, through: size.width, by: 32) {
                                var line = Path()
                                line.move(to: CGPoint(x: x, y: 0))
                                line.addLine(to: CGPoint(x: x, y: size.height))
                                context.stroke(line, with: .color(.cyan.opacity(0.12)), lineWidth: 0.5)
                            }
                            for y in stride(from: 0.0, through: size.height, by: 32) {
                                var line = Path()
                                line.move(to: CGPoint(x: 0, y: y))
                                line.addLine(to: CGPoint(x: size.width, y: y))
                                context.stroke(line, with: .color(.cyan.opacity(0.12)), lineWidth: 0.5)
                            }
                        }
                    }
                }
            }.frame(width: geo.size.width, height: geo.size.height).clipped()
        }
    }
}

final class BackgroundSettings: ObservableObject {
    @Published var selected: String {
        didSet {
            defaults.set(selected, forKey: "background.selected")
            scheduleRotation()
            publishWidgetBackground()
        }
    }
    static let rotationIntervals = [0, 1, 5, 15, 30, 60]
    @Published var rotationMinutes: Int {
        didSet {
            defaults.set(rotationMinutes, forKey: "background.rotationMinutes")
            scheduleRotation()
        }
    }
    @Published var rotationCategory: String {
        didSet { defaults.set(rotationCategory, forKey: "background.rotationCategory") }
    }
    private var timer: Timer?
    @Published var dim: Double {
        didSet {
            defaults.set(dim, forKey: "background.dim")
            publishWidgetBackground()
        }
    }
    @Published private(set) var customImage: NSImage?
    private let defaults: UserDefaults
    private let customURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("DesktopTodo/CustomBackground.jpg")
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let minutes = defaults.integer(forKey: "background.rotationMinutes")
        rotationMinutes = Self.rotationIntervals.contains(minutes) ? minutes : 0
        let storedCategory = defaults.string(forKey: "background.rotationCategory") ?? "全部"
        let category = ["GG", "小屁", "合体"].contains(storedCategory) ? "GG和小屁" : storedCategory
        rotationCategory = Wallpaper.all.first { $0.category == category }?.category ?? "全部"
        selected = defaults.string(forKey: "background.selected") ?? "original"
        dim = defaults.object(forKey: "background.dim") as? Double ?? 0.25
        customImage = NSImage(contentsOf: customURL)
        defaults.set(rotationCategory, forKey: "background.rotationCategory")
        if selected == "custom" && customImage == nil { selected = "original" }
        scheduleRotation()
        publishWidgetBackground()
    }

    deinit { timer?.invalidate() }

    private func scheduleRotation() {
        timer?.invalidate()
        timer = nil
        guard rotationMinutes > 0 else { return }
        let next = Timer(timeInterval: Double(rotationMinutes) * 60, repeats: false) { [weak self] _ in
            guard let self else { return }
            let candidates = Wallpaper.all.filter {
                $0.id != self.selected && (self.rotationCategory == "全部" || $0.category == self.rotationCategory)
            }
            if let wallpaper = candidates.randomElement() { selected = wallpaper.id }
        }
        timer = next
        RunLoop.main.add(next, forMode: .common)
    }

    private func publishWidgetBackground() {
        // A bounded image keeps widget timelines small, including for imported photos.
        let size = NSSize(width: 960, height: 720)
        let image = NSImage(size: size)
        image.lockFocus()
        let bounds = NSRect(origin: .zero, size: size)
        if let source = selected == "custom" ? customImage : wallpaper.file.flatMap({ NSImage(named: $0) }) {
            let scale = max(size.width / source.size.width, size.height / source.size.height)
            let target = NSRect(x: (size.width - source.size.width * scale) / 2,
                                y: (size.height - source.size.height * scale) / 2,
                                width: source.size.width * scale, height: source.size.height * scale)
            source.draw(in: target)
        } else {
            NSGradient(colors: wallpaper.colors.map { NSColor($0) })?.draw(in: bounds, angle: -45)
        }
        // Keep white task labels readable even when the main background is very bright.
        NSColor.black.withAlphaComponent(max(0.32, dim)).setFill()
        bounds.fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return }
        do {
            let file = customURL.deletingLastPathComponent().appendingPathComponent("WidgetBackground.jpg")
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            WidgetCenter.shared.reloadTimelines(ofKind: TodoWidgetID.kind)
        } catch {
            NSLog("Widget background update failed: %@", error.localizedDescription)
        }
    }

    var wallpaper: Wallpaper { Wallpaper.all.first { $0.id == selected } ?? Wallpaper.all[0] }
    func chooseLocal() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .heic, .tiff]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let image = NSImage(contentsOf: url),
                  let representation = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: representation),
                  let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try FileManager.default.createDirectory(at: customURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: customURL, options: .atomic)
            customImage = image
            selected = "custom"
        } catch { NSAlert(error: error).runModal() }
    }
}

struct TaskBackground: View {
    @ObservedObject var settings: BackgroundSettings
    var body: some View {
        GeometryReader { geo in
            ZStack {
                if settings.selected == "custom", let image = settings.customImage {
                    Image(nsImage: image).resizable().scaledToFill()
                } else { WallpaperSurface(wallpaper: settings.wallpaper) }
                Color.black.opacity(settings.dim)
            }.frame(width: geo.size.width, height: geo.size.height).clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct BackgroundPreferences: View {
    @ObservedObject var settings: BackgroundSettings
    @Environment(\.dismiss) private var dismiss
    @State private var category = "全部"
    private let categories = ["全部", "GG和小屁", "炫酷", "田园", "风景", "动漫", "科技"]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("背景设置").font(.title2.bold())
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(categories, id: \.self) { item in
                        Button { category = item } label: {
                            Text(item).font(.subheadline.weight(category == item ? .semibold : .regular))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(category == item ? Color.teal.opacity(0.16) : .clear, in: Capsule())
                                .contentShape(Capsule())
                        }.buttonStyle(.plain)
                            .accessibilityAddTraits(category == item ? .isSelected : [])
                    }
                }
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    ForEach(Wallpaper.all.filter { category == "全部" || $0.category == category }) { wallpaper in
                        Button { settings.selected = wallpaper.id } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                WallpaperSurface(wallpaper: wallpaper)
                                    .frame(height: 105).clipShape(RoundedRectangle(cornerRadius: 9))
                                    .overlay(alignment: .topTrailing) {
                                        if settings.selected == wallpaper.id {
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, .teal).padding(7)
                                        }
                                    }
                                Text(wallpaper.name).font(.subheadline).foregroundStyle(.primary)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
            Divider()
            HStack {
                Picker("定时更换", selection: $settings.rotationMinutes) {
                    ForEach(BackgroundSettings.rotationIntervals, id: \.self) { minutes in
                        Text(minutes == 0 ? "关闭" : "每 \(minutes) 分钟").tag(minutes)
                    }
                }.fixedSize()
                Spacer()
                if settings.rotationMinutes > 0 {
                    Picker("壁纸范围", selection: $settings.rotationCategory) {
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }.fixedSize()
                }
            }
            HStack {
                Button("选择本地图片…", action: settings.chooseLocal)
                if settings.selected == "custom" { Text("使用本地图片").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("恢复默认") {
                    settings.rotationMinutes = 0
                    settings.rotationCategory = "全部"
                    settings.selected = "original"
                    settings.dim = 0.25
                }
            }
            HStack {
                Text("背景遮罩").font(.subheadline)
                Slider(value: $settings.dim, in: 0...0.65)
                Text("\(Int(settings.dim * 100))%").monospacedDigit().frame(width: 35)
            }
        }.padding(22).frame(width: 520, height: 490)
    }
}
