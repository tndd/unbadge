import AppKit

struct ResolvedApp {
    let entry: BadgeEntry
    let url: URL
    let name: String
}

enum ApplicationCatalog {
    static func resolve(_ entry: BadgeEntry, lookup: (String) -> URL? = {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
    }) -> ResolvedApp? {
        guard !entry.id.hasPrefix("_SYSTEM_CENTER_:") else { return nil }
        let candidates = [lookup(entry.id), entry.path.map { URL(fileURLWithPath: $0) }].compactMap { $0 }
        for candidate in candidates {
            let url = candidate.standardizedFileURL
            let parents = url.deletingLastPathComponent().pathComponents
            guard url.pathExtension.lowercased() == "app",
                  !parents.contains(where: { $0.lowercased().hasSuffix(".app") || $0.lowercased().hasSuffix(".framework") }),
                  !parents.contains(where: { ["Contents", "XPCServices", "Helpers", "LoginItems"].contains($0) }),
                  let bundle = Bundle(url: url), bundle.bundleIdentifier == entry.id,
                  let executable = bundle.executableURL,
                  FileManager.default.isExecutableFile(atPath: executable.path),
                  (bundle.object(forInfoDictionaryKey: "LSBackgroundOnly") as? NSNumber)?.boolValue != true else { continue }
            // メニューバーアプリも対象。Passwords.app などは APPL 型とは限らない。
            let name = entry.id == BadgeStore.settingsDomain ? "システム設定" :
                (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
                 FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
            return ResolvedApp(entry: entry, url: url, name: name)
        }
        return nil
    }
}
