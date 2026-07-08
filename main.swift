import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let maxEntries = 10
    private var statusItem: NSStatusItem!
    private var history: [String] = []
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var timer: Timer?

    // Pasteboard types that mark content we should never keep:
    // "Concealed" is set by password managers, "Transient" by apps that
    // don't want their copies recorded (see nspasteboard.org).
    private static let skippedTypes: [NSPasteboard.PasteboardType] = [
        .init("org.nspasteboard.ConcealedType"),
        .init("org.nspasteboard.TransientType"),
    ]

    private let historyURL: URL = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CopyPal", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadHistory()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "doc.on.clipboard",
                                   accessibilityDescription: "CopyPal") {
                button.image = image
            } else {
                button.title = "📋"
            }
        }
        rebuildMenu()

        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
        timer?.tolerance = 0.15
    }

    private func checkPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        if let types = pb.types, Self.skippedTypes.contains(where: types.contains) {
            return
        }
        guard let text = pb.string(forType: .string), !text.isEmpty else { return }

        history.removeAll { $0 == text }
        history.insert(text, at: 0)
        if history.count > maxEntries {
            history.removeLast(history.count - maxEntries)
        }
        saveHistory()
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        if history.isEmpty {
            menu.addItem(NSMenuItem(title: "No clipboard history yet", action: nil, keyEquivalent: ""))
        } else {
            for (index, entry) in history.enumerated() {
                let key = index < 9 ? String(index + 1) : "0"
                let item = NSMenuItem(title: Self.menuTitle(for: entry),
                                      action: #selector(copyEntry(_:)),
                                      keyEquivalent: key)
                item.keyEquivalentModifierMask = []
                item.target = self
                item.representedObject = entry
                item.toolTip = String(entry.prefix(1000))
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
        menu.addItem(NSMenuItem(title: "Quit CopyPal",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private static func menuTitle(for entry: String) -> String {
        let oneLine = entry
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return oneLine.count > 50 ? String(oneLine.prefix(50)) + "…" : oneLine
    }

    @objc private func copyEntry(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        // The poll timer will see this change and move the entry to the top.
    }

    @objc private func clearHistory() {
        history.removeAll()
        saveHistory()
        rebuildMenu()
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyURL),
              let saved = try? JSONDecoder().decode([String].self, from: data) else { return }
        history = Array(saved.prefix(maxEntries))
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        try? data.write(to: historyURL, options: .atomic)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
