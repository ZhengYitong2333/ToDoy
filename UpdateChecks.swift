import Foundation
import CryptoKit

func runUpdateChecks() throws {
    precondition(AppVersion("v1.6.0") == AppVersion("1.6"))
    precondition(AppVersion("1.10.0")! > AppVersion("1.9.9")!)
    for invalid in ["", "1..0", "1.2.3-beta", "1.2.3.4", "../../1", "1.-2.3"] {
        precondition(AppVersion(invalid) == nil)
    }
    func release(_ version: String, draft: Bool = false, prerelease: Bool = false) throws -> AppRelease {
        let payload: [String: Any] = ["tag_name": version, "body": "测试说明", "draft": draft,
                                     "prerelease": prerelease, "assets": []]
        return try JSONDecoder().decode(AppRelease.self, from: JSONSerialization.data(withJSONObject: payload))
    }
    let newer = try release("v1.6.0")
    precondition(newer.isNewer(than: "1.5.1"))
    precondition(!newer.isNewer(than: "1.6.0") && !newer.isNewer(than: "1.7.0"))
    let draft = try release("v2.0.0", draft: true), beta = try release("v2.0.0", prerelease: true)
    precondition(!draft.isNewer(than: "1.0.0") && !beta.isNewer(than: "1.0.0"))
    precondition(newer.package == nil)
    precondition(AppRelease.trustedDownload(URL(string: "https://github.com/ZhengYitong2333/ToDoy/releases/download/v1.6.0/ToDoy-1.6.0.dmg")!))
    for bad in ["http://github.com/ZhengYitong2333/ToDoy/releases/download/a", "https://example.com/file.dmg",
                "https://github.com/other/ToDoy/releases/download/a", "https://user:pass@github.com/ZhengYitong2333/ToDoy/releases/download/a"] {
        precondition(!AppRelease.trustedDownload(URL(string: bad)!))
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("todoy-update-check-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let dmg = root.appendingPathComponent("corrupt.dmg")
    try Data("corrupt".utf8).write(to: dmg)
    do {
        _ = try UpdateFiles.prepare(dmg: dmg, root: root, version: "1.6.0", digest: "sha256:" + String(repeating: "0", count: 64))
        preconditionFailure("Corrupt download accepted")
    } catch let error as UpdateFailure { precondition(error.message.contains("校验失败")) }
    precondition(!FileManager.default.fileExists(atPath: root.appendingPathComponent("mount").path))
    print("Update version ordering, stable releases, asset origin and corrupt-download checks OK")
}
