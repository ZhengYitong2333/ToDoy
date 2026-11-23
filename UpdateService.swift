import SwiftUI
import CryptoKit
import Network

struct AppVersion: Comparable {
    let parts: [Int]
    init?(_ value: String) {
        let text = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let fields = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(fields.count), fields.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              fields.allSatisfy({ Int($0) != nil }) else { return nil }
        parts = fields.map { Int($0)! } + Array(repeating: 0, count: 3 - fields.count)
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}

struct AppRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
        let digest: String?
        let size: Int
    }
    let tag_name: String
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
    var version: String { tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name }
    var package: Asset? { assets.first { $0.name == "ToDoy-\(version).dmg" } }
    func isNewer(than current: String) -> Bool {
        guard !draft, !prerelease, let remote = AppVersion(version), let local = AppVersion(current) else { return false }
        return remote > local
    }
    static func trustedDownload(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.user == nil && url.password == nil &&
        url.path.hasPrefix("/ZhengYitong2333/ToDoy/releases/download/")
    }
}

struct UpdateFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// Runs off the UI thread. Arguments are never interpolated into shell commands.
enum UpdateFiles {
    static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateFailure(message: "安装包处理失败，请重试或从 Release 页面下载。") }
    }
    static func validate(_ app: URL, version: String) throws {
        var hostBuild: String?
        for (bundle, identifier) in [(app, "local.desktop.todo.panel"),
            (app.appendingPathComponent("Contents/PlugIns/TodoWidget.appex"), "local.desktop.todo.panel.widget")] {
            let data = try Data(contentsOf: bundle.appendingPathComponent("Contents/Info.plist"))
            guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  info["CFBundleIdentifier"] as? String == identifier,
                  info["CFBundleShortVersionString"] as? String == version else {
                throw UpdateFailure(message: "安装包的应用或版本不匹配，已停止更新。")
            }
            guard let build = info["CFBundleVersion"] as? String, !build.isEmpty else {
                throw UpdateFailure(message: "安装包缺少构建版本。")
            }
            if let hostBuild, hostBuild != build { throw UpdateFailure(message: "主程序与小组件版本不一致。") }
            hostBuild = build
            guard let executable = info["CFBundleExecutable"] as? String, !executable.contains("/") else {
                throw UpdateFailure(message: "安装包缺少可执行程序。")
            }
            #if arch(arm64)
            let architecture = "arm64"
            #else
            let architecture = "x86_64"
            #endif
            try run("/usr/bin/lipo", [bundle.appendingPathComponent("Contents/MacOS/\(executable)").path, "-verify_arch", architecture])
            if let minimum = info["LSMinimumSystemVersion"] as? String, let required = AppVersion(minimum) {
                let os = ProcessInfo.processInfo.operatingSystemVersion
                guard AppVersion("\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")! >= required else {
                    throw UpdateFailure(message: "新版需要 macOS \(minimum) 或以上。")
                }
            }
        }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
    }
    static func prepare(dmg: URL, root: URL, version: String, digest: String, installedApp: URL? = nil) throws -> URL {
        let hash = SHA256.hash(data: try Data(contentsOf: dmg, options: .mappedIfSafe))
            .map { String(format: "%02x", $0) }.joined()
        guard digest == "sha256:\(hash)" else { throw UpdateFailure(message: "下载文件校验失败，请重新下载。") }
        let mount = root.appendingPathComponent("mount")
        let source = mount.appendingPathComponent("ToDoy.app")
        let candidate = root.appendingPathComponent("ToDoy.app")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        defer {
            let registrar = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
            try? run(registrar, ["-u", source.path])
            try? run(registrar, ["-u", candidate.path])
            try? run("/usr/bin/hdiutil", ["detach", mount.path])
            if let installedApp, installedApp.pathExtension == "app" { try? run(registrar, ["-f", installedApp.path]) }
        }
        try run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", mount.path, dmg.path])
        try validate(source, version: version)
        try run("/usr/bin/ditto", [source.path, candidate.path])
        try validate(candidate, version: version)
        return candidate
    }
}

private final class DownloadProgress: NSObject, URLSessionDownloadDelegate {
    let changed: @Sendable (Double) -> Void
    init(_ changed: @escaping @Sendable (Double) -> Void) { self.changed = changed }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 { changed(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))) }
    }
}

@MainActor final class UpdateService: ObservableObject {
    static let releasesURL = URL(string: "https://github.com/ZhengYitong2333/ToDoy/releases/latest")!
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    @Published private(set) var available: AppRelease?
    @Published private(set) var checking = false
    @Published private(set) var phase: String?
    @Published private(set) var progress = 0.0
    @Published private(set) var error: String?
    @Published private(set) var lastChecked: Date?
    @Published private(set) var ready: URL?
    @Published var automatic = UserDefaults.standard.object(forKey: "updates.automatic") as? Bool ?? true {
        didSet { UserDefaults.standard.set(automatic, forKey: "updates.automatic") }
    }
    @Published var proxy = UserDefaults.standard.string(forKey: "updates.proxy") ?? "" {
        didSet { UserDefaults.standard.set(proxy, forKey: "updates.proxy") }
    }
    private func session() throws -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 600
        let address = proxy.trimmingCharacters(in: .whitespacesAndNewlines)
        if !address.isEmpty {
            guard let url = URL(string: address), let host = url.host, let port = url.port,
                  let portValue = UInt16(exactly: port), portValue > 0, let nwPort = NWEndpoint.Port(rawValue: portValue),
                  url.user == nil, url.password == nil,
                  (url.path.isEmpty || url.path == "/"), url.query == nil, url.fragment == nil,
                  let scheme = url.scheme, ["http", "https", "socks5", "socks5h"].contains(scheme) else {
                throw UpdateFailure(message: "代理地址格式不正确，例如 socks5://127.0.0.1:7897。")
            }
            let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)
            configuration.proxyConfigurations = [scheme.hasPrefix("socks")
                ? ProxyConfiguration(socksv5Proxy: endpoint)
                : ProxyConfiguration(httpCONNECTProxy: endpoint, tlsOptions: scheme == "https" ? NWProtocolTLS.Options() : nil)]
        }
        return URLSession(configuration: configuration)
    }
    private var lastAttempt = Date.distantPast
    private var operation: Task<Void, Never>?
    private var workspace: URL?
    private var timer: Timer?
    var hasUpdate: Bool { available != nil }
    init() {
        if let data = UserDefaults.standard.data(forKey: "updates.lastRelease"),
           let release = try? JSONDecoder().decode(AppRelease.self, from: data), release.isNewer(than: currentVersion) {
            available = release
        }
        lastChecked = UserDefaults.standard.object(forKey: "updates.lastChecked") as? Date
    }
    private func retryConnection<T>(_ action: () async throws -> T) async throws -> T {
        do { return try await action() }
        catch let error as URLError where [.networkConnectionLost, .timedOut, .secureConnectionFailed,
                                          .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed].contains(error.code) {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(500))
            return try await action()
        }
    }
    private var resultFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DesktopTodo/update-result.txt")
    }
    @MainActor func start() {
        if let text = try? String(contentsOf: resultFile, encoding: .utf8) {
            error = text
            try? FileManager.default.removeItem(at: resultFile)
        }
        checkAutomatically()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkAutomatically() }
        }
    }
    @MainActor func checkAutomatically() {
        guard automatic, Date().timeIntervalSince(lastAttempt) >= 900 else { return }
        check()
    }
    @MainActor func check() {
        guard !checking, phase == nil, ready == nil else { return }
        checking = true
        lastAttempt = Date()
        Task { @MainActor in
            defer { checking = false }
            do {
                let session = try session()
                defer { session.finishTasksAndInvalidate() }
                var request = URLRequest(url: URL(string: "https://api.github.com/repos/ZhengYitong2333/ToDoy/releases/latest")!)
                request.timeoutInterval = 25
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("ToDoy/\(currentVersion)", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await retryConnection { try await session.data(for: request) }
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw UpdateFailure(message: "暂时无法检查更新，请稍后重试。")
                }
                let release = try JSONDecoder().decode(AppRelease.self, from: data)
                available = release.isNewer(than: currentVersion) ? release : nil
                lastChecked = Date()
                UserDefaults.standard.set(data, forKey: "updates.lastRelease")
                UserDefaults.standard.set(lastChecked, forKey: "updates.lastChecked")
                // Keep installer recovery messages visible until the next user action.
                if error?.hasPrefix("更新安装失败") != true { error = nil }
            } catch { self.error = "检查更新失败：\(error.localizedDescription)" }
        }
    }
    @MainActor func download() {
        guard let release = available, phase == nil, ready == nil, !checking else { return }
        guard let asset = release.package, AppRelease.trustedDownload(asset.browser_download_url),
              let digest = asset.digest, digest.range(of: "^sha256:[0-9a-f]{64}$", options: .regularExpression) != nil else {
            error = "新版尚未上传完整的通用安装包，请稍后检查或打开 Release 页面。"; return
        }
        phase = "正在下载更新…"; error = nil; progress = 0
        operation = Task { @MainActor [self] in
            let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ToDoy/Updates.noindex/\(UUID().uuidString)")
            do {
                let session = try session()
                defer { session.finishTasksAndInvalidate() }
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                var request = URLRequest(url: asset.browser_download_url)
                request.timeoutInterval = 120
                let delegate = DownloadProgress { [weak self] value in
                    Task { @MainActor in self?.progress = value }
                }
                let (temporary, response) = try await retryConnection { try await session.download(for: request, delegate: delegate) }
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw UpdateFailure(message: "下载失败，请重试。")
                }
                let dmg = root.appendingPathComponent("update.dmg")
                try FileManager.default.moveItem(at: temporary, to: dmg)
                let size = try FileManager.default.attributesOfItem(atPath: dmg.path)[.size] as? NSNumber
                guard size?.intValue == asset.size else { throw UpdateFailure(message: "安装包下载不完整，请重试。") }
                try Task.checkCancellation()
                phase = "正在校验安装包…"
                let installed = Bundle.main.bundleURL
                let candidate = try await Task.detached {
                    try UpdateFiles.prepare(dmg: dmg, root: root, version: release.version, digest: digest, installedApp: installed)
                }.value
                try Task.checkCancellation()
                workspace = root; ready = candidate
            } catch {
                try? FileManager.default.removeItem(at: root)
                if !(error is CancellationError), (error as? URLError)?.code != .cancelled {
                    self.error = error.localizedDescription
                }
            }
            phase = nil; operation = nil
        }
    }
    @MainActor func cancelDownload() { operation?.cancel() }
    @MainActor func install() -> Bool {
        guard let ready, let workspace, phase == nil else { return false }
        let target = Bundle.main.bundleURL.resolvingSymlinksInPath()
        guard target.pathExtension == "app", !target.path.hasPrefix("/Volumes/"),
              !target.path.contains("/AppTranslocation/"),
              FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
            error = "请先将 ToDoy 安装到有写入权限的应用程序目录，再重试更新。"; return false
        }
        do {
            guard let helper = Bundle.main.url(forResource: "install-update", withExtension: "sh") else {
                throw UpdateFailure(message: "缺少更新安装程序，请从 Release 页面下载安装。")
            }
            let copy = workspace.appendingPathComponent("install-update.sh")
            if FileManager.default.fileExists(atPath: copy.path) { try FileManager.default.removeItem(at: copy) }
            try FileManager.default.copyItem(at: helper, to: copy)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [copy.path, String(ProcessInfo.processInfo.processIdentifier), ready.path, target.path, resultFile.path]
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run()
            phase = "正在重新启动…"
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}

