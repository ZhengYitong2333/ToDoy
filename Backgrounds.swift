import SwiftUI
import UniformTypeIdentifiers

struct Wallpaper: Identifiable {
    let id: String
    let name: String
    let category: String
    let file: String?
    let colors: [Color]
    static let all: [Wallpaper] = [
        .init(id: "original", name: "流动色彩", category: "炫酷", file: "Landscape", colors: []),
        .init(id: "aurora", name: "极光", category: "炫酷", file: nil, colors: [.black, .indigo, .purple, .mint]),
        .init(id: "pastoral", name: "湖畔晨光", category: "田园", file: "pastoral", colors: []),
        .init(id: "meadow", name: "青野", category: "田园", file: nil, colors: [.init(red: 0.06, green: 0.22, blue: 0.18), .green, .yellow.opacity(0.5)]),
        .init(id: "mountain", name: "群山", category: "风景", file: "mountain", colors: []),
        .init(id: "anime", name: "海边列车", category: "动漫", file: "anime", colors: [.indigo, .pink]),
        .init(id: "cyber", name: "数字夜幕", category: "科技", file: nil, colors: [.black, .init(red: 0.02, green: 0.15, blue: 0.28), .cyan.opacity(0.6)]),
        .init(id: "plasma", name: "星际", category: "科技", file: nil, colors: [.black, .indigo, .blue])
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
    @Published var selected: String { didSet { defaults.set(selected, forKey: "background.selected") } }
    @Published var dim: Double { didSet { defaults.set(dim, forKey: "background.dim") } }
    @Published private(set) var customImage: NSImage?
    private let defaults = UserDefaults.standard
    private let customURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("DesktopTodo/CustomBackground.jpg")
    init() {
        selected = UserDefaults.standard.string(forKey: "background.selected") ?? "original"
        dim = UserDefaults.standard.object(forKey: "background.dim") as? Double ?? 0.25
        customImage = NSImage(contentsOf: customURL)
        if selected == "custom" && customImage == nil { selected = "original" }
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
    }
}

struct BackgroundPreferences: View {
    @ObservedObject var settings: BackgroundSettings
    @Environment(\.dismiss) private var dismiss
    @State private var category = "全部"
    private let categories = ["全部", "炫酷", "田园", "风景", "动漫", "科技"]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("背景设置").font(.title2.bold())
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Picker("分类", selection: $category) {
                ForEach(categories, id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
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
                Button("选择本地图片…", action: settings.chooseLocal)
                if settings.selected == "custom" { Text("使用本地图片").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("恢复默认") { settings.selected = "original"; settings.dim = 0.25 }
            }
            HStack {
                Text("背景遮罩").font(.subheadline)
                Slider(value: $settings.dim, in: 0...0.65)
                Text("\(Int(settings.dim * 100))%").monospacedDigit().frame(width: 35)
            }
        }.padding(22).frame(width: 520, height: 490)
    }
}
