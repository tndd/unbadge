import Foundation
import CoreFoundation

// Dock の並び順ではなくアプリの識別子で特定し、GUID を含む保存値を照合する。
struct SettingsDockTile {
    static let domain = "com.apple.dock"
    static let key = "persistent-apps"
    let rows: [[String: Any]]
    let index: Int
    let enabled: Bool
    private let data: [String: Any]

    init(_ value: Any?) throws {
        guard let rows = value as? [[String: Any]] else {
            throw BadgeError.message("Dockのアプリ一覧を読み取れません。変更を中止しました。")
        }
        let matches = rows.indices.filter {
            (rows[$0]["tile-data"] as? [String: Any])?["bundle-identifier"] as? String == BadgeStore.settingsDomain
        }
        guard matches.count == 1, let index = matches.first else {
            throw BadgeError.message(matches.isEmpty
                ? "システム設定をDockに固定すると、バッジの継続非表示を設定できます。"
                : "Dockのシステム設定を一意に特定できません。重複した登録を確認してください。")
        }
        guard let data = rows[index]["tile-data"] as? [String: Any],
              let enabled = Self.badgeValue(data["dock-extra"]),
              Self.identifier(rows[index]["GUID"]) != nil else {
            throw BadgeError.message("Dockのシステム設定が未対応の形式です。変更を中止しました。")
        }
        self.rows = rows
        self.index = index
        self.enabled = enabled
        self.data = data
    }

    static func badgeValue(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
    static func identifier(_ value: Any?) -> NSNumber? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.int64Value > 0, number.doubleValue == Double(number.int64Value) else { return nil }
        return number
    }
    func settingBadge(_ enabled: Bool) -> [[String: Any]] {
        var updated = rows
        var data = self.data
        data["dock-extra"] = enabled
        updated[index]["tile-data"] = data
        return updated
    }
}
