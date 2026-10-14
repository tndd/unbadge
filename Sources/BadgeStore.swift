import Foundation
import CoreFoundation

enum BadgeError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

protocol Preferences {
    func read(_ domain: String, _ key: String) throws -> Any?
    func write(_ domain: String, _ key: String, _ value: Any?) throws
}

final class SystemPreferences: Preferences {
    func read(_ domain: String, _ key: String) throws -> Any? {
        guard CFPreferencesSynchronize(domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            throw BadgeError.message("設定を読み直せません。変更を中止しました。")
        }
        return CFPreferencesCopyValue(key as CFString, domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
    func write(_ domain: String, _ key: String, _ value: Any?) throws {
        guard !CFPreferencesAppValueIsForced(key as CFString, domain as CFString) else {
            throw BadgeError.message("管理されている設定のため変更できません。")
        }
        CFPreferencesSetValue(key as CFString, value as CFPropertyList?, domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard CFPreferencesSynchronize(domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            throw BadgeError.message("設定の保存に失敗しました。復元記録は保持しています。")
        }
    }
}

struct BadgeEntry {
    let id: String
    let path: String?
    let enabled: Bool
}

final class BadgeStore {
    static let notificationDomain = "com.apple.ncprefs"
    static let settingsDomain = "com.apple.systempreferences"
    static let attentionKey = "AttentionPrefBundleIDs"
    private let prefs: Preferences
    private let journalURL: URL
    private let permitWrites: Bool
    private var journal: [String: Any]
    static let mask: UInt64 = 2

    init(prefs: Preferences, journalURL: URL, permitWrites: Bool) throws {
        self.prefs = prefs
        self.journalURL = journalURL
        self.permitWrites = permitWrites
        if FileManager.default.fileExists(atPath: journalURL.path) {
            guard let value = try PropertyListSerialization.propertyList(from: Data(contentsOf: journalURL), format: nil) as? [String: Any] else {
                throw BadgeError.message("復元記録を読み込めません。記録を保護するため変更を中止します。")
            }
            journal = value
        } else { journal = [:] }
    }

    private func saveJournal(_ value: [String: Any]) throws {
        try FileManager.default.createDirectory(at: journalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
        try data.write(to: journalURL, options: .atomic)
        journal = value
    }
    private func requireWrites() throws {
        guard permitWrites else { throw BadgeError.message("書き込みは macOS 15.8.1 のみ対応しています。") }
    }
    private func rows() throws -> [[String: Any]] {
        guard let rows = try prefs.read(Self.notificationDomain, "apps") as? [[String: Any]], !rows.isEmpty else {
            throw BadgeError.message("通知設定を読み込めません。未対応の形式、またはアクセス制限の可能性があります。")
        }
        return rows
    }
    private func flags(_ row: [String: Any]) throws -> UInt64 {
        guard let n = row["flags"] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.int64Value >= 0 else {
            throw BadgeError.message("通知設定の形式が想定と異なります。")
        }
        return n.uint64Value
    }
    func entries() throws -> [BadgeEntry] {
        try rows().compactMap { row in
            guard let id = row["bundle-id"] as? String else { return nil }
            return BadgeEntry(id: id, path: row["path"] as? String, enabled: try flags(row) & Self.mask != 0)
        }
    }
    func hasUndo(_ id: String) -> Bool { (journal["badges"] as? [String: Bool])?[id] != nil }
    var hasSettingsUndo: Bool { journal["attention"] != nil }

    func setBadge(_ id: String, enabled: Bool, record: Bool = true) throws {
        try requireWrites()
        var list = try rows()
        let originalRows = list
        let matches = list.indices.filter { list[$0]["bundle-id"] as? String == id }
        guard matches.count == 1, let index = matches.first else {
            throw BadgeError.message("対象アプリの設定を一意に特定できません。再読み込みしてください。")
        }
        let original = try flags(list[index])
        guard (original & Self.mask != 0) != enabled else { return }
        if record {
            var next = journal
            var badges = next["badges"] as? [String: Bool] ?? [:]
            if badges[id] == nil { badges[id] = original & Self.mask != 0 }
            next["badges"] = badges
            try saveJournal(next)
        }
        list[index]["flags"] = NSNumber(value: enabled ? original | Self.mask : original & ~Self.mask)
        guard NSArray(array: try rows()).isEqual(to: originalRows) else {
            throw BadgeError.message("通知設定が別の処理で変わりました。再読み込みしてからやり直してください。")
        }
        try prefs.write(Self.notificationDomain, "apps", list)
        guard let readBack = try prefs.read(Self.notificationDomain, "apps") as? [[String: Any]],
              NSArray(array: readBack).isEqual(to: list) else {
            throw BadgeError.message("保存結果が一致しません。設定が同時に更新された可能性があります。復元記録は保持しています。")
        }
    }

    func restoreBadge(_ id: String) throws {
        guard let original = (journal["badges"] as? [String: Bool])?[id] else { return }
        try setBadge(id, enabled: original, record: false)
        var next = journal
        var badges = next["badges"] as? [String: Bool] ?? [:]
        badges.removeValue(forKey: id)
        next["badges"] = badges
        try saveJournal(next)
    }

    func attention() throws -> [String: Any] {
        guard let value = try prefs.read(Self.settingsDomain, Self.attentionKey) else { return [:] }
        guard let result = value as? [String: Any], result.values.allSatisfy({ $0 is NSNumber }) else {
            throw BadgeError.message("システム設定のバッジ情報が未対応の形式です。")
        }
        return result
    }
    func clearSettings() throws {
        try requireWrites()
        let current = try attention()
        let active = current.filter { ($0.value as? NSNumber)?.intValue != 0 }
        guard !active.isEmpty else { return }
        var next = journal
        var saved = next["attention"] as? [String: Any] ?? [:]
        for (key, value) in active where saved[key] == nil { saved[key] = value }
        next["attention"] = saved
        try saveJournal(next)
        var updated = current
        for key in active.keys { updated[key] = 0 }
        guard NSDictionary(dictionary: try attention()).isEqual(to: current) else {
            throw BadgeError.message("バッジ情報が更新されました。再読み込みしてからやり直してください。")
        }
        try prefs.write(Self.settingsDomain, Self.attentionKey, updated)
        guard NSDictionary(dictionary: try attention()).isEqual(to: updated) else {
            throw BadgeError.message("解除状態の保存を確認できません。復元記録は保持しています。")
        }
    }
    func restoreSettings() throws {
        try requireWrites()
        guard let saved = journal["attention"] as? [String: Any] else { return }
        var current = try attention()
        let previous = current
        // macOS が後から生成した値は上書きせず、解除したままの項目だけ戻す。
        for (key, value) in saved where (current[key] as? NSNumber)?.intValue == 0 { current[key] = value }
        guard NSDictionary(dictionary: try attention()).isEqual(to: previous) else {
            throw BadgeError.message("バッジ情報が更新されました。再読み込みしてからやり直してください。")
        }
        try prefs.write(Self.settingsDomain, Self.attentionKey, current)
        guard NSDictionary(dictionary: try attention()).isEqual(to: current) else {
            throw BadgeError.message("復元結果を確認できません。復元記録は保持しています。")
        }
        var next = journal
        next.removeValue(forKey: "attention")
        try saveJournal(next)
    }
}
