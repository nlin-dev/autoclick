// Minecraft background autoclicker. Run: swift autoclick.swift
import AppKit

struct Target { let pid: pid_t; let window: CGWindowID; let center: CGPoint }

func commandLine(_ pid: pid_t) -> String {
    let p = Process(), out = Pipe()
    p.executableURL = URL(fileURLWithPath: "/bin/ps")
    p.arguments = ["-ww", "-o", "command=", "-p", "\(pid)"]
    p.standardOutput = out
    try? p.run(); p.waitUntilExit()
    return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
}

// The game window is a normal-layer window owned by a process whose command line mentions minecraft
// (Modrinth/vanilla/Prism all pass minecraft paths or -Dminecraft.* flags to java).
func findMinecraft() -> Target? {
    let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    for w in list where w[kCGWindowLayer as String] as? Int == 0 {
        guard let pid = w[kCGWindowOwnerPID as String] as? pid_t,
              let id = w[kCGWindowNumber as String] as? CGWindowID,
              let b = w[kCGWindowBounds as String] as? NSDictionary,
              let r = CGRect(dictionaryRepresentation: b), r.width > 200, r.height > 200,
              commandLine(pid).lowercased().contains("minecraft") else { continue }
        return Target(pid: pid, window: id, center: CGPoint(x: r.midX, y: r.midY))
    }
    return nil
}

// Window-under-pointer fields: route the click to Minecraft's window even though it's in the background.
let windowFields = [91, 92].map { unsafeBitCast(UInt32($0), to: CGEventField.self) }

func post(_ t: Target, _ button: CGMouseButton, down: Bool) {
    let type: CGEventType = button == .left ? (down ? .leftMouseDown : .leftMouseUp)
                                            : (down ? .rightMouseDown : .rightMouseUp)
    guard let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: t.center, mouseButton: button) else { return }
    e.setIntegerValueField(.mouseEventClickState, value: 1)
    for f in windowFields { e.setIntegerValueField(f, value: Int64(t.window)) }
    e.postToPid(t.pid)
}

final class App: NSObject, NSApplicationDelegate {
    let button = NSSegmentedControl(labels: ["Left", "Right"], trackingMode: .selectOne, target: nil, action: nil)
    let mode = NSSegmentedControl(labels: ["Hold", "Click every"], trackingMode: .selectOne, target: nil, action: nil)
    let interval = NSTextField(string: "0.5")
    let startStop = NSButton(title: "Start", target: nil, action: nil)
    let status = NSTextField(labelWithString: "")
    var window: NSWindow!
    var timer: Timer?
    var active: (Target, CGMouseButton)?

    func applicationDidFinishLaunching(_: Notification) {
        button.selectedSegment = 0
        mode.selectedSegment = 1
        interval.widthAnchor.constraint(equalToConstant: 60).isActive = true
        startStop.target = self; startStop.action = #selector(toggle)
        startStop.keyEquivalent = "\r"
        let row = NSStackView(views: [mode, interval, NSTextField(labelWithString: "seconds")])
        let stack = NSStackView(views: [button, row, startStop, status])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Autoclick"
        window.contentView = stack
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if !CGPreflightPostEventAccess() { CGRequestPostEventAccess() }
        status.stringValue = findMinecraft().map { "Minecraft found (pid \($0.pid))" } ?? "Minecraft not found"
    }

    @objc func toggle() { active == nil ? start() : stop() }

    func start() {
        guard CGPreflightPostEventAccess() else {
            status.stringValue = "Grant Accessibility to your terminal app, then restart"; return
        }
        guard let t = findMinecraft() else { status.stringValue = "Minecraft not found"; return }
        let b: CGMouseButton = button.selectedSegment == 0 ? .left : .right
        if mode.selectedSegment == 0 {
            post(t, b, down: true)
            status.stringValue = "Holding \(b == .left ? "left" : "right")…"
        } else {
            guard let s = Double(interval.stringValue), s >= 0.05 else {
                status.stringValue = "Interval must be a number ≥ 0.05"; return
            }
            timer = Timer.scheduledTimer(withTimeInterval: s, repeats: true) { _ in
                post(t, b, down: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { post(t, b, down: false) }
            }
            timer?.fire()
            status.stringValue = "Clicking \(b == .left ? "left" : "right") every \(s)s…"
        }
        active = (t, b)
        startStop.title = "Stop"
        [button, mode, interval].forEach { $0.isEnabled = false }
    }

    // Always release the button so it never stays stuck down in-game.
    func stop() {
        timer?.invalidate(); timer = nil
        if let (t, b) = active { post(t, b, down: false) }
        active = nil
        startStop.title = "Start"
        status.stringValue = "Stopped"
        [button, mode, interval].forEach { $0.isEnabled = true }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { true }
    func applicationWillTerminate(_: Notification) { stop() }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.regular)
// Ctrl+C in the terminal: release the button before exiting.
signal(SIGINT, SIG_IGN)
let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sigint.setEventHandler { delegate.stop(); exit(0) }
sigint.resume()
app.run()
