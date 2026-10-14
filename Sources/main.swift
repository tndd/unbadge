import AppKit
import ApplicationServices

final class BackgroundStack: NSStackView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        super.draw(dirtyRect)
    }
}

final class ActionButton: NSButton {
    var actionBlock: (() -> Void)?
    convenience init(_ title: String, action: @escaping () -> Void) {
        self.init(title: title, target: nil, action: #selector(invoke))
        self.target = self
        self.bezelStyle = .rounded
        self.actionBlock = action
    }
    @objc func invoke() { actionBlock?() }
}

final class BadgeSwitch: NSSwitch {
    var actionBlock: ((Bool) -> Void)?
    @objc func invoke() { actionBlock?(state == .on) }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 700), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    let table = NSTableView()
    let search = NSSearchField()
    let status = NSTextField(wrappingLabelWithString: "")
    let systemStatus = NSTextField(labelWithString: "")
    var store: BadgeStore?
    var entries: [BadgeEntry] = []
    var filtered: [BadgeEntry] = []
    var names: [String: String] = [:]
    var icons: [String: NSImage] = [:]
    var systemRestore: ActionButton!
    var systemClear: ActionButton!
    let supported: Bool = {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return version.majorVersion == 15 && version.minorVersion == 8 && version.patchVersion == 1
    }()
    var canWrite: Bool { supported && store != nil }

    func label(_ text: String, size: CGFloat = 13, bold: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        return field
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu()
        let item = NSMenuItem()
        menu.addItem(item)
        item.submenu = NSMenu(title: "Badge Control")
        item.submenu?.addItem(withTitle: "Badge Control を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenuItem(title: "編集", action: nil, keyEquivalent: "")
        edit.submenu = NSMenu(title: "編集")
        for (title, selector, key) in [("切り取り", "cut:", "x"), ("コピー", "copy:", "c"), ("ペースト", "paste:", "v"), ("すべて選択", "selectAll:", "a")] {
            edit.submenu?.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }
        menu.addItem(edit)
        NSApp.mainMenu = menu
        window.title = "Badge Control — 実験版"
        window.minSize = NSSize(width: 720, height: 700)
        window.center()
        buildUI()
        do {
            let journal = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/BadgeControl/undo.plist")
            store = try BadgeStore(prefs: SystemPreferences(), journalURL: journal, permitWrites: supported)
            try reload()
            showStatus(supported ? "設定を読み込みました。切替は保存後に通知サービスを再起動して反映します。" : "このOSは未対応です。表示のみ利用できます。", error: false)
        } catch { showStatus(error.localizedDescription, error: true) }
        updateButtons()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > i + 1 {
            let path = CommandLine.arguments[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
                if let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    window.effectiveAppearance.performAsCurrentDrawingAppearance {
                        view.cacheDisplay(in: view.bounds, to: rep)
                    }
                    if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)) }
                }
                print("表示行数: \(entries.count)、書込対応: \(supported)、アクセシビリティ許可: \(AXIsProcessTrusted())")
                NSApp.terminate(nil)
            }
        }
    }
    func buildUI() {
        let root = BackgroundStack()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 20, right: 24)
        window.contentView = root
        root.addArrangedSubview(label("バッジを、必要なものだけ。", size: 25, bold: true))
        let note = label("macOS 15.8.1 向け実験版。通知音・バナーはそのままに、Dockの通知バッジを個別に切り替えます。独自描画のバッジには効かない場合があります。")
        note.textColor = .secondaryLabelColor
        root.addArrangedSubview(note)

        let box = NSBox()
        box.titlePosition = .noTitle
        box.contentViewMargins = NSSize(width: 12, height: 12)
        box.heightAnchor.constraint(equalToConstant: 150).isActive = true
        let group = NSStackView()
        group.orientation = .vertical
        group.alignment = .leading
        group.spacing = 8
        group.addArrangedSubview(label("システム設定", size: 14, bold: true))
        group.addArrangedSubview(systemStatus)
        group.addArrangedSubview(label("現在のバッジを解除します。OSが再表示することがあります。\n解除時にDockを再起動します。アップデートの検出・インストール設定は変更しません。", size: 12))
        systemClear = ActionButton("現在のバッジを解除") { [weak self] in self?.perform(system: true) { try self?.store?.clearSettings() } }
        systemRestore = ActionButton("解除前に戻す") { [weak self] in self?.perform(system: true) { try self?.store?.restoreSettings() } }
        group.addArrangedSubview(NSStackView(views: [systemClear, systemRestore]))
        let container = NSView()
        box.contentView = container
        container.addSubview(group)
        group.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            group.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            group.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            group.topAnchor.constraint(equalTo: container.topAnchor),
            group.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor)
        ])
        root.addArrangedSubview(box)

        search.placeholderString = "アプリ名・識別子で検索"
        search.delegate = self
        root.addArrangedSubview(search)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        table.rowHeight = 53
        table.usesAlternatingRowBackgroundColors = true
        table.dataSource = self
        table.delegate = self
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        for (id, title, width) in [("app", "アプリ", 452.0), ("badge", "バッジ", 92.0), ("undo", "元の設定", 120.0)] {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title
            col.width = width
            col.minWidth = id == "app" ? 300 : width
            table.addTableColumn(col)
        }
        scroll.documentView = table
        root.addArrangedSubview(scroll)
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        let refresh = ActionButton("再読み込み") { [weak self] in
            do { try self?.reload(); self?.showStatus("現在の保存値を読み込みました。Dock上の表示とは異なる場合があります。", error: false) }
            catch { self?.showStatus(error.localizedDescription, error: true) }
        }
        let settings = ActionButton("macOSの通知設定を開く") {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
        }
        root.addArrangedSubview(NSStackView(views: [refresh, settings]))
        status.font = .systemFont(ofSize: 12)
        status.setContentCompressionResistancePriority(.required, for: .vertical)
        root.addArrangedSubview(status)
        for view in [note, box, search, scroll, status] {
            view.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -48).isActive = true
        }
    }
    func reload() throws {
        guard let store else { return }
        entries = try store.entries().filter { !$0.id.hasPrefix("_SYSTEM_CENTER_:") }
        for entry in entries where names[entry.id] == nil {
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.id) ?? entry.path.map { URL(fileURLWithPath: $0) }
            if let url, FileManager.default.fileExists(atPath: url.path) {
                names[entry.id] = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
                icons[entry.id] = NSWorkspace.shared.icon(forFile: url.path)
            } else { names[entry.id] = entry.id }
        }
        entries.sort {
            let a = icons[$0.id] != nil, b = icons[$1.id] != nil
            if a != b { return a }
            return (names[$0.id] ?? $0.id).localizedStandardCompare(names[$1.id] ?? $1.id) == .orderedAscending
        }
        do {
            let active = try store.attention().values.filter { ($0 as? NSNumber)?.intValue != 0 }.count
            systemStatus.stringValue = active > 0 ? "バッジの元になる項目：\(active)件" : "保存されたバッジ項目はありません"
        } catch { systemStatus.stringValue = error.localizedDescription }
        filter()
        updateButtons()
    }
    func updateButtons() {
        systemClear.isEnabled = canWrite
        systemRestore.isEnabled = canWrite && (store?.hasSettingsUndo ?? false)
    }
    func filter() {
        let query = search.stringValue
        filtered = entries.filter { query.isEmpty || (names[$0.id] ?? "").localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query) }
        table.reloadData()
    }
    func controlTextDidChange(_ obj: Notification) { filter() }
    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = filtered[row]
        if tableColumn?.identifier.rawValue == "badge" {
            let toggle = BadgeSwitch()
            toggle.state = entry.enabled ? .on : .off
            toggle.isEnabled = canWrite
            toggle.target = toggle
            toggle.action = #selector(BadgeSwitch.invoke)
            toggle.setAccessibilityLabel("\(names[entry.id] ?? entry.id) のバッジ")
            toggle.actionBlock = { [weak self] enabled in self?.perform { try self?.store?.setBadge(entry.id, enabled: enabled) } }
            return toggle
        }
        if tableColumn?.identifier.rawValue == "undo" {
            let button = ActionButton("元に戻す") { [weak self] in self?.perform { try self?.store?.restoreBadge(entry.id) } }
            button.isEnabled = canWrite && (store?.hasUndo(entry.id) ?? false)
            return button
        }
        let icon = NSImageView()
        icon.image = icons[entry.id] ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)
        icon.widthAnchor.constraint(equalToConstant: 30).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 30).isActive = true
        let text = NSStackView(views: [label(names[entry.id] ?? entry.id, bold: true), label(entry.id, size: 10)])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3
        let rowView = NSStackView(views: [icon, text])
        rowView.spacing = 10
        rowView.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 0)
        return rowView
    }
    func restart(_ name: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["-u", NSUserName(), name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw BadgeError.message("設定は保存しましたが、\(name) を再起動できません。ログアウト後に反映を確認してください。") }
    }
    func perform(system: Bool = false, _ operation: () throws -> Void) {
        do {
            try operation()
            try reload()
            try restart(system ? "Dock" : "usernoted")
            showStatus("設定の保存と\(system ? "Dock" : "通知サービス")の再起動が完了しました。実際のバッジ表示を確認してください。", error: false)
        } catch {
            try? reload()
            showStatus(error.localizedDescription, error: true)
        }
    }
    func showStatus(_ text: String, error: Bool) {
        status.stringValue = text
        status.textColor = error ? .systemRed : .secondaryLabelColor
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
