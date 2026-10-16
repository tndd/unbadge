import Foundation

final class MemoryPreferences: Preferences {
    var domains: [String: [String: Any]] = [:]
    var writes = 0
    var discardWrite = false
    var beforeRead: ((String, String) -> Void)?
    var afterWrite: ((String, String) -> Void)?
    func read(_ domain: String, _ key: String) throws -> Any? {
        beforeRead?(domain, key)
        return domains[domain]?[key]
    }
    func write(_ domain: String, _ key: String, _ value: Any?) throws {
        writes += 1
        if !discardWrite { domains[domain, default: [:]][key] = value }
        afterWrite?(domain, key)
    }
    var rows: [[String: Any]] {
        get { domains[BadgeStore.notificationDomain]?["apps"] as? [[String: Any]] ?? [] }
        set { domains[BadgeStore.notificationDomain, default: [:]]["apps"] = newValue }
    }
    var dockRows: [[String: Any]] {
        get { domains[SettingsDockTile.domain]?[SettingsDockTile.key] as? [[String: Any]] ?? [] }
        set { domains[SettingsDockTile.domain, default: [:]][SettingsDockTile.key] = newValue }
    }
}

func dockTile(_ id: String = BadgeStore.settingsDomain, guid: Int = 24, enabled: Bool = true) -> [String: Any] {
    ["GUID": guid, "tile-type": "file-tile", "tile-data": [
        "bundle-identifier": id, "dock-extra": enabled, "file-label": "テスト用アプリ",
        "book": Data([0, 1, 2]), "file-data": ["_CFURLString": "file:///System/Applications/System%20Settings.app/", "_CFURLStringType": 15]
    ]]
}

var count = 0
func check(_ value: Bool, _ message: String) {
    guard value else { print("失敗: \(message)"); exit(1) }
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
let preservedRows = p.rows
p.dockRows = [dockTile("other.app", guid: 12), dockTile()]
let preservedAttention = try reopened.attention()
try reopened.setBadge(BadgeStore.settingsDomain, enabled: false)
let disabledSystem = try reopened.entries().first { $0.id == BadgeStore.settingsDomain }
check(disabledSystem?.enabled == false, "共通一覧のシステム設定がオフになる")
check(reopened.hasUndo(BadgeStore.settingsDomain), "共通の復元ボタンが有効になる")
check(NSDictionary(dictionary: try reopened.attention()).isEqual(to: preservedAttention), "継続非表示は通知数を変更しない")
p.domains[BadgeStore.settingsDomain]?[BadgeStore.attentionKey] = ["regenerated": 9]
check(reopened.settingsEntry().enabled == false, "OSが通知数を再生成しても継続非表示のまま")
try reopened.setBadge(BadgeStore.settingsDomain, enabled: true)
let enabledSystem = try reopened.entries().first { $0.id == BadgeStore.settingsDomain }
check(enabledSystem?.enabled == true, "共通スイッチでシステム設定を復元")
try reopened.setBadge(BadgeStore.settingsDomain, enabled: false)
try reopened.restoreBadge(BadgeStore.settingsDomain)
check(!reopened.hasUndo(BadgeStore.settingsDomain), "共通の復元操作で記録を終了")
check(NSArray(array: p.rows).isEqual(to: preservedRows), "システム設定の共通操作で他アプリの設定を保持")
p.domains[BadgeStore.settingsDomain]?[BadgeStore.attentionKey] = [:] as [String: Any]
try reopened.setBadge(BadgeStore.settingsDomain, enabled: false)
check(reopened.settingsEntry().enabled == false, "通知数がゼロでも今後の非表示を設定できる")
try reopened.setBadge(BadgeStore.settingsDomain, enabled: true)
check(try reopened.attention().isEmpty, "表示許可を戻しても新しい通知数は作らない")
try reopened.restoreBadge(BadgeStore.settingsDomain)
p.domains[BadgeStore.settingsDomain]?[BadgeStore.attentionKey] = "unexpected"
expectError("形式不明のシステム設定") { try reopened.clearSettings() }
p.rows = [["bundle-id": "test.app", "flags": true]]
expectError("不正なフラグ") { _ = try reopened.entries() }
p.rows = [["bundle-id": "test.app", "flags": 3], ["bundle-id": "test.app", "flags": 3]]
expectError("重複ID") { try reopened.setBadge("test.app", enabled: false) }

// 実際のDockや通知設定を書き換えずに、保存と後からのOS更新を再現する。
func dockFixture(_ name: String, enabled: Bool = true) throws -> (MemoryPreferences, BadgeStore, URL) {
    let prefs = MemoryPreferences()
    prefs.rows = [["bundle-id": "test.app", "flags": 3]]
    prefs.dockRows = [dockTile("other.app", guid: 12), dockTile(enabled: enabled)]
    prefs.domains[SettingsDockTile.domain]?["unrelated"] = "保持"
    let url = root.appendingPathComponent(name + ".plist")
    return (prefs, try BadgeStore(prefs: prefs, journalURL: url, permitWrites: true), url)
}
let (dp, ds, dj) = try dockFixture("persistent")
let dockBefore = dp.dockRows
try ds.setBadge(BadgeStore.settingsDomain, enabled: false)
var expectedDock = dockBefore
var expectedData = expectedDock[1]["tile-data"] as! [String: Any]
expectedData["dock-extra"] = false
expectedDock[1]["tile-data"] = expectedData
check(NSArray(array: dp.dockRows).isEqual(to: expectedDock), "対象のdock-extraだけを変更し、並び順・ブックマーク・別アプリを保持")
check(dp.domains[SettingsDockTile.domain]?["unrelated"] as? String == "保持", "Dockの別キーを保持")
let dockWrites = dp.writes
try ds.setBadge(BadgeStore.settingsDomain, enabled: false)
check(dp.writes == dockWrites, "すでに非表示なら書き込まない")
let dsReopened = try BadgeStore(prefs: dp, journalURL: dj, permitWrites: true)
check(!dsReopened.settingsEntry().enabled && dsReopened.hasSettingsUndo, "アプリ再起動後もオフと復元記録を読み込む")
check(dp.writes == dockWrites, "起動・読み込みでは自動書き込みをしない")
var movedTile = dp.dockRows[1]
var movedData = movedTile["tile-data"] as! [String: Any]
movedData["file-label"] = "後からの変更"
movedTile["tile-data"] = movedData
dp.dockRows = [movedTile, dockTile("added.app", guid: 99), dp.dockRows[0]]
try dsReopened.restoreBadge(BadgeStore.settingsDomain)
let movedAfter = try SettingsDockTile(dp.dockRows)
check(movedAfter.index == 0 && movedAfter.enabled, "Dockの並べ替え後もアプリ識別子で元の値へ復元")
check((dp.dockRows[0]["tile-data"] as? [String: Any])?["file-label"] as? String == "後からの変更" && dp.dockRows.count == 3,
      "復元時は後からの変更と追加されたアプリを保持")
check(!dsReopened.hasSettingsUndo, "Dockの復元成功後に記録を消す")
let (offPrefs, offStore, _) = try dockFixture("originally-off", enabled: false)
try offStore.setBadge(BadgeStore.settingsDomain, enabled: true)
try offStore.setBadge(BadgeStore.settingsDomain, enabled: false)
try offStore.setBadge(BadgeStore.settingsDomain, enabled: true)
try offStore.restoreBadge(BadgeStore.settingsDomain)
check(try SettingsDockTile(offPrefs.dockRows).enabled == false, "元からオフの設定も繰り返し操作後に正しく復元")

let (readdedPrefs, readdedStore, _) = try dockFixture("readded")
try readdedStore.setBadge(BadgeStore.settingsDomain, enabled: false)
readdedPrefs.dockRows = [dockTile(guid: 71)]
try readdedStore.setBadge(BadgeStore.settingsDomain, enabled: false)
try readdedStore.restoreBadge(BadgeStore.settingsDomain)
check(try SettingsDockTile(readdedPrefs.dockRows).enabled, "同じアプリをDockへ追加し直した後も再設定と復元ができる")

var invalidDockCases: [Any] = ["unexpected", [dockTile("other.app")], [dockTile(), dockTile(guid: 25)]]
var noFlag = dockTile()
var noFlagData = noFlag["tile-data"] as! [String: Any]
noFlagData.removeValue(forKey: "dock-extra")
noFlag["tile-data"] = noFlagData
invalidDockCases.append([noFlag])
var numericFlag = dockTile()
var numericData = numericFlag["tile-data"] as! [String: Any]
numericData["dock-extra"] = 1
numericFlag["tile-data"] = numericData
invalidDockCases.append([numericFlag])
var invalidGUID = dockTile()
invalidGUID["GUID"] = true
invalidDockCases.append([invalidGUID])
for (index, value) in invalidDockCases.enumerated() {
    let (prefs, store, url) = try dockFixture("invalid-\(index)")
    prefs.domains[SettingsDockTile.domain]?[SettingsDockTile.key] = value
    check(store.settingsEntry().disabledReason != nil, "Dock形式不明・対象不明では理由を表示（\(index)）")
    check(try store.entries().contains { $0.id == "test.app" }, "Dock対象不明でも通常アプリ一覧を維持（\(index)）")
    expectError("Dock形式不明・対象不明の書込（\(index)）") { try store.setBadge(BadgeStore.settingsDomain, enabled: false) }
    check(prefs.writes == 0 && !FileManager.default.fileExists(atPath: url.path), "特定できない対象には書き込まず復元記録も作らない（\(index)）")
}
let (missingPrefs, missingStore, _) = try dockFixture("missing-after-disable")
try missingStore.setBadge(BadgeStore.settingsDomain, enabled: false)
missingPrefs.dockRows = [dockTile("other.app")]
let missingWrites = missingPrefs.writes
expectError("解除後に対象がなくなった復元") { try missingStore.restoreBadge(BadgeStore.settingsDomain) }
check(missingStore.hasSettingsUndo && missingPrefs.writes == missingWrites, "対象が消えた場合は別アプリに触らず復元記録を保持")

let (backupPrefs, _, _) = try dockFixture("backup-failure")
let backupStore = try BadgeStore(prefs: backupPrefs, journalURL: file.appendingPathComponent("dock.plist"), permitWrites: true)
expectError("Dockバックアップ失敗") { try backupStore.setBadge(BadgeStore.settingsDomain, enabled: false) }
check(backupPrefs.writes == 0, "Dockもバックアップできるまで書き込まない")
let blockedStore = try BadgeStore(prefs: backupPrefs, journalURL: root.appendingPathComponent("unsupported-dock.plist"), permitWrites: false)
expectError("未対応OSのDock変更") { try blockedStore.setBadge(BadgeStore.settingsDomain, enabled: false) }
check(backupPrefs.writes == 0, "未対応OSではDockを書き換えない")

let (discardPrefs, discardStore, _) = try dockFixture("discard")
discardPrefs.discardWrite = true
expectError("Dock保存不一致") { try discardStore.setBadge(BadgeStore.settingsDomain, enabled: false) }
check(discardStore.hasSettingsUndo && discardStore.settingsEntry().enabled, "保存失敗を成功扱いにせず実状態と復元記録を保持")
discardPrefs.discardWrite = false
try discardStore.setBadge(BadgeStore.settingsDomain, enabled: false)
discardPrefs.dockRows = [dockTile()]
expectError("Dock再起動後の設定リセット") { try discardStore.verifySettingsDockBadge(false) }

let (racePrefs, raceStore, _) = try dockFixture("race")
var dockReads = 0
racePrefs.beforeRead = { domain, key in
    if domain == SettingsDockTile.domain && key == SettingsDockTile.key {
        dockReads += 1
        if dockReads == 2 { racePrefs.dockRows.reverse() }
    }
}
expectError("Dock保存直前の並び替え") { try raceStore.setBadge(BadgeStore.settingsDomain, enabled: false) }
check(racePrefs.writes == 0 && raceStore.hasSettingsUndo, "保存前の競合を検出し他のDock変更を上書きしない")
let (latePrefs, lateStore, _) = try dockFixture("late-race")
latePrefs.afterWrite = { domain, _ in
    if domain == SettingsDockTile.domain { latePrefs.dockRows = [dockTile()] }
}
expectError("Dock保存直後の同時更新") { try lateStore.setBadge(BadgeStore.settingsDomain, enabled: false) }
check(lateStore.hasSettingsUndo, "保存直後の競合でも復元記録を保持")

let (corruptPrefs, _, corruptURL) = try dockFixture("corrupt-journal")
try PropertyListSerialization.data(fromPropertyList: ["settingsDock": "unexpected"], format: .xml, options: 0).write(to: corruptURL)
let corruptStore = try BadgeStore(prefs: corruptPrefs, journalURL: corruptURL, permitWrites: true)
expectError("不正なDock復元記録の変更") { try corruptStore.setBadge(BadgeStore.settingsDomain, enabled: false) }
expectError("不正なDock復元記録の復元") { try corruptStore.restoreBadge(BadgeStore.settingsDomain) }
check(corruptPrefs.writes == 0 && corruptStore.hasSettingsUndo, "不正な復元記録を上書きしない")

let legacyPrefs = MemoryPreferences()
legacyPrefs.domains[BadgeStore.settingsDomain] = [BadgeStore.attentionKey: ["old": 0, "new": 7]]
let legacyURL = root.appendingPathComponent("legacy.plist")
try PropertyListSerialization.data(fromPropertyList: ["attention": ["old": 1]], format: .xml, options: 0).write(to: legacyURL)
let legacyStore = try BadgeStore(prefs: legacyPrefs, journalURL: legacyURL, permitWrites: true)
try legacyStore.restoreBadge(BadgeStore.settingsDomain)
let legacyAttention = try legacyStore.attention()
check(legacyAttention["old"] as? Int == 1 && legacyAttention["new"] as? Int == 7,
      "Dockに固定されていなくても旧版の復元記録は利用でき、新しい通知数を保持")
check(!legacyStore.hasSettingsUndo, "旧版の復元成功後も記録を終了")

func fixture(_ relative: String, id: String, extra: [String: Any] = [:]) throws -> URL {
    let url = root.appendingPathComponent(relative)
    let contents = url.appendingPathComponent("Contents")
    let executable = contents.appendingPathComponent("MacOS/Fixture")
    try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
    var info: [String: Any] = ["CFBundleIdentifier": id, "CFBundleExecutable": "Fixture", "CFBundlePackageType": "APPL"]
    info.merge(extra) { _, new in new }
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    return url
}
func resolve(_ url: URL, id: String) -> ResolvedApp? {
    ApplicationCatalog.resolve(BadgeEntry(id: id, path: url.path, enabled: true), lookup: { _ in nil })
}
let ordinary = try fixture("Visible.app", id: "test.visible")
check(resolve(ordinary, id: "test.visible") != nil, "実在する通常アプリを表示")
let menuApp = try fixture("Menu.app", id: "test.menu", extra: ["LSUIElement": true])
check(resolve(menuApp, id: "test.menu") != nil, "メニューバーアプリを残す")
let xpcApp = try fixture("PasswordLike.app", id: "test.passwords", extra: ["CFBundlePackageType": "XPC!"])
check(resolve(xpcApp, id: "test.passwords") != nil, "Passwordsと同型の実アプリを残す")
let service = try fixture("Service.bundle", id: "test.service")
check(resolve(service, id: "test.service") == nil, "通知サービスのbundleを除外")
let helper = try fixture("Parent.app/Contents/Helpers/Helper.app", id: "test.helper")
check(resolve(helper, id: "test.helper") == nil, "内部の補助アプリを除外")
let background = try fixture("Background.app", id: "test.background", extra: ["LSBackgroundOnly": true])
check(resolve(background, id: "test.background") == nil, "バックグラウンド専用アプリを除外")
check(resolve(ordinary, id: "test.mismatch") == nil, "識別子が一致しない参照先を除外")
check(resolve(root.appendingPathComponent("Missing.app"), id: "test.missing") == nil, "実体のない登録を除外")
check(ApplicationCatalog.resolve(BadgeEntry(id: "_SYSTEM_CENTER_:test", path: ordinary.path, enabled: true), lookup: { _ in ordinary }) == nil, "内部サービス登録を除外")
print("\(count)項目の検証に成功。実際のユーザー設定は変更していません。")
