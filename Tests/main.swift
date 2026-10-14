import Foundation

final class MemoryPreferences: Preferences {
    var domains: [String: [String: Any]] = [:]
    var writes = 0
    var discardWrite = false
    func read(_ domain: String, _ key: String) throws -> Any? { domains[domain]?[key] }
    func write(_ domain: String, _ key: String, _ value: Any?) throws {
        writes += 1
        if !discardWrite { domains[domain, default: [:]][key] = value }
    }
    var rows: [[String: Any]] {
        get { domains[BadgeStore.notificationDomain]?["apps"] as? [[String: Any]] ?? [] }
        set { domains[BadgeStore.notificationDomain, default: [:]]["apps"] = newValue }
    }
}

var count = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    guard value() else { print("失敗: \(message)"); exit(1) }
    count += 1
}
func expectError(_ label: String, _ action: () throws -> Void) {
    do { try action(); print("失敗: エラーが必要（\(label)）"); exit(1) }
    catch { count += 1 }
}
let root = FileManager.default.temporaryDirectory.appendingPathComponent("BadgeControlTests-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let p = MemoryPreferences()
let original: UInt64 = 9_521_594_382
p.rows = [["bundle-id": "test.app", "flags": NSNumber(value: original), "auth": 791], ["bundle-id": "other.app", "flags": 41]]
p.domains[BadgeStore.notificationDomain]?["unrelated"] = "保持"
let journal = root.appendingPathComponent("undo.plist")
let store = try BadgeStore(prefs: p, journalURL: journal, permitWrites: true)
try store.setBadge("test.app", enabled: false)
check((p.rows[0]["flags"] as? NSNumber)?.uint64Value == original & ~2, "64bit のバッジビットだけ変更")
check(p.rows[0]["auth"] as? Int == 791 && p.rows[1]["flags"] as? Int == 41, "権限と別アプリを保持")
check(p.domains[BadgeStore.notificationDomain]?["unrelated"] as? String == "保持", "別キーを保持")
check(store.hasUndo("test.app"), "復元記録を保存")
var rows = p.rows
rows[0]["flags"] = NSNumber(value: (original & ~2) ^ 32)
p.rows = rows
let reopened = try BadgeStore(prefs: p, journalURL: journal, permitWrites: true)
try reopened.restoreBadge("test.app")
check((p.rows[0]["flags"] as? NSNumber)?.uint64Value == original ^ 32, "再起動後の復元で新しい無関係なビットを保持")
check(!reopened.hasUndo("test.app"), "成功した復元記録を消す")
try reopened.setBadge("test.app", enabled: false)
try reopened.setBadge("test.app", enabled: true)
try reopened.setBadge("test.app", enabled: false)
try reopened.restoreBadge("test.app")
check((p.rows[0]["flags"] as? NSNumber)?.uint64Value == original ^ 32, "繰り返し操作でも最初の状態に復元")
let priorWrites = p.writes
expectError("存在しないアプリ") { try store.setBadge("missing", enabled: false) }
check(p.writes == priorWrites, "対象不明では書き込まない")
let unsupported = try BadgeStore(prefs: p, journalURL: root.appendingPathComponent("unsupported.plist"), permitWrites: false)
expectError("未対応OS") { try unsupported.setBadge("test.app", enabled: false) }
check(p.writes == priorWrites, "未対応OSでは書き込まない")
p.discardWrite = true
expectError("保存不一致") { try reopened.setBadge("test.app", enabled: false) }
check(reopened.hasUndo("test.app"), "保存失敗後も復元記録を保持")
p.discardWrite = false
let file = root.appendingPathComponent("not-a-directory")
try Data("x".utf8).write(to: file)
let badJournal = try BadgeStore(prefs: p, journalURL: file.appendingPathComponent("undo.plist"), permitWrites: true)
let beforeBackupFailure = p.writes
expectError("バックアップ不可") { try badJournal.setBadge("test.app", enabled: false) }
check(p.writes == beforeBackupFailure, "バックアップ前に設定を書き換えない")
p.domains[BadgeStore.settingsDomain] = [BadgeStore.attentionKey: ["first": 1, "second": 2, "zero": 0], "other": "保持"]
try reopened.clearSettings()
let cleared = try reopened.attention()
check(cleared["first"] as? Int == 0 && cleared["second"] as? Int == 0, "システム設定の解除")
check(p.domains[BadgeStore.settingsDomain]?["other"] as? String == "保持", "システム設定の別キーを保持")
p.domains[BadgeStore.settingsDomain]?[BadgeStore.attentionKey] = ["first": 0, "second": 7, "zero": 0, "new": 3]
try reopened.restoreSettings()
let restored = try reopened.attention()
check(restored["first"] as? Int == 1, "解除した項目の復元")
check(restored["second"] as? Int == 7 && restored["new"] as? Int == 3, "macOSが後から更新した値を保持")
check(!reopened.hasSettingsUndo, "システム設定復元記録を終了")
p.domains[BadgeStore.settingsDomain]?[BadgeStore.attentionKey] = "unexpected"
expectError("形式不明のシステム設定") { try reopened.clearSettings() }
p.rows = [["bundle-id": "test.app", "flags": true]]
expectError("不正なフラグ") { _ = try reopened.entries() }
p.rows = [["bundle-id": "test.app", "flags": 3], ["bundle-id": "test.app", "flags": 3]]
expectError("重複ID") { try reopened.setBadge("test.app", enabled: false) }
print("\(count)項目の検証に成功。実際のユーザー設定は変更していません。")
