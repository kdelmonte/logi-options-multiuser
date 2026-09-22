import Cocoa

// Persistent menu-bar status for the Logi session guard.
//
// The guard writes a small key=value state file; this renders it as a coloured dot.
//   state=ready|settling|inactive|error
//   owner=<username that currently holds the mouse>
//   deadline=<unix epoch, only while settling>
//
// Dot colours:  green = this session has the mouse and it has settled
//               amber = settling, with seconds remaining
//               grey  = another account holds the mouse
//               red   = Options+ never reported pairing

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var infoItem: NSMenuItem!
    private var ownerItem: NSMenuItem!

    private let stateFile = NSHomeDirectory() + "/Library/Caches/logi-guard/state"
    private let me = NSUserName()

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.isVisible = true

        let menu = NSMenu()
        infoItem  = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
        ownerItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        infoItem.isEnabled = false
        ownerItem.isEnabled = false
        menu.addItem(infoItem)
        menu.addItem(ownerItem)
        menu.addItem(.separator())
        let logItem = NSMenuItem(title: "Open guard log", action: #selector(openLog), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)
        statusItem.menu = menu

        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    @objc private func openLog() {
        let p = NSHomeDirectory() + "/Library/Logs/logi-session-guard.log"
        NSWorkspace.shared.open(URL(fileURLWithPath: p))
    }

    private func readState() -> [String: String] {
        guard let raw = try? String(contentsOfFile: stateFile, encoding: .utf8) else { return [:] }
        var d: [String: String] = [:]
        for line in raw.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { d[parts[0].trimmingCharacters(in: .whitespaces)] =
                                   parts[1].trimmingCharacters(in: .whitespaces) }
        }
        return d
    }

    private func render(dot: NSColor, suffix: String) {
        // negative kern pulls the dot tight against the mouse glyph
        let s = NSMutableAttributedString(string: "\u{1F5B1}", attributes: [.kern: -3.0])
        s.append(NSAttributedString(string: "\u{25CF}", attributes: [
            .foregroundColor: dot,
            .font: NSFont.systemFont(ofSize: 9)
        ]))
        if !suffix.isEmpty {
            s.append(NSAttributedString(string: " " + suffix, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            ]))
        }
        statusItem.button?.attributedTitle = s
    }

    private func tick() {
        let st = readState()
        let state = st["state"] ?? "unknown"
        let owner = st["owner"] ?? "?"

        switch state {
        case "settling":
            let deadline = Double(st["deadline"] ?? "") ?? 0
            let remaining = Int(ceil(deadline - Date().timeIntervalSince1970))
            if remaining > 0 {
                render(dot: .systemOrange, suffix: "\(remaining)s")
                infoItem.title = "Mouse settling — \(remaining)s remaining"
            } else {
                render(dot: .systemGreen, suffix: "")
                infoItem.title = "Mouse ready"
            }
            ownerItem.title = "Held by \(owner)"

        case "ready":
            render(dot: .systemGreen, suffix: "")
            infoItem.title  = "Mouse ready"
            ownerItem.title = "Held by \(owner)"

        case "inactive":
            render(dot: .tertiaryLabelColor, suffix: "")
            infoItem.title  = "Mouse held by another account"
            ownerItem.title = owner == "?" ? "" : "Currently: \(owner)"

        case "error":
            render(dot: .systemRed, suffix: "!")
            infoItem.title  = "Options+ never reported pairing"
            ownerItem.title = "Check the guard log"

        default:
            render(dot: .tertiaryLabelColor, suffix: "")
            infoItem.title  = "Waiting for guard…"
            ownerItem.title = ""
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
