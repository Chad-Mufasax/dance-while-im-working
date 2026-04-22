import AppKit
import ApplicationServices

final class PromptDetector {
    private let state: AppState
    private var timer: Timer?

    private let pollInterval: TimeInterval = 1.0
    private let autoPressCooldown: TimeInterval = 3.0
    private let maxDepth = 40
    /// We only need the tail (see `tailSize`). Capping the collected buffer
    /// keeps AX tree walks cheap even on terminals with huge scrollback.
    private let textBudget = 6_000

    /// Apps we bother scanning. Non-terminal apps cannot host a Claude Code
    /// prompt, so walking their AX trees is pure waste. Keep this list
    /// focused on real terminals + the common IDEs with integrated ones.
    private let terminalBundles: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "dev.warp.Warp",
        "net.kovidgoyal.kitty",
        "io.alacritty",
        "com.github.wez.wezterm",
        "co.zeit.hyper",
        "dev.zed.Zed",
        "dev.kiro.desktop",
        "com.microsoft.VSCode",
        "com.visualstudio.code.oss",
        "com.jetbrains.toolbox",
        "com.todesktop.230313mzl4w4u92", // Cursor
    ]

    private func isTerminal(_ app: NSRunningApplication) -> Bool {
        guard let id = app.bundleIdentifier else { return false }
        return terminalBundles.contains(id)
    }

    /// Phrases that identify a **live** Claude Code permission prompt.
    /// All three markers must appear in the *tail* of the terminal buffer:
    /// - "Esc to cancel · Tab to amend" — the live TUI footer; scrollback
    ///   after the prompt is dismissed does not keep this line.
    /// - "Do you want to proceed?" — the question.
    /// - A numbered "Yes" option — either selected or unselected.
    ///
    /// Matching on the tail only is critical: terminals with large
    /// scrollback buffers (Ghostty, iTerm2) expose the entire history via
    /// the Accessibility API, so historical prompts or pasted screenshots
    /// containing the prompt text would otherwise false-positive forever.
    private let liveFooter = "Esc to cancel · Tab to amend"
    private let question   = "Do you want to proceed?"
    private let yesMarkers = ["❯ 1. Yes", "1. Yes"]
    private let tailSize   = 3000

    /// PID of the process currently displaying the prompt, once confirmed.
    /// Enter is only ever posted to this PID.
    private var lockedPid: pid_t?
    private var lockedStreak: Int = 0
    private let confirmTicks = 2 // need N consecutive detections before auto-press

    init(state: AppState) {
        self.state = state
    }

    func start() {
        promptForAccessibilityIfNeeded()
        let t = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func promptForAccessibilityIfNeeded() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    private func tick() {
        if state.paused {
            if state.isDancing { state.isDancing = false }
            lockedPid = nil
            lockedStreak = 0
            return
        }

        let matchPid = findPromptPid()
        let isMatch = matchPid != nil

        if isMatch != state.isDancing {
            state.isDancing = isMatch
        }

        guard let pid = matchPid else {
            lockedPid = nil
            lockedStreak = 0
            return
        }

        if lockedPid == pid {
            lockedStreak += 1
        } else {
            lockedPid = pid
            lockedStreak = 1
        }

        if state.autoPressEnter && lockedStreak >= confirmTicks {
            let now = Date()
            if let last = state.lastAutoPressAt, now.timeIntervalSince(last) < autoPressCooldown {
                return
            }
            state.lastAutoPressAt = now
            KeyPresser.pressReturn(pid: pid)
        }
    }

    /// Walks every visible regular app's windows and returns the PID of the
    /// one whose UI contains the Claude permission prompt, or nil.
    /// This intentionally does NOT require the terminal to be frontmost —
    /// that lets the user work elsewhere while the app still detects the prompt.
    private func findPromptPid() -> pid_t? {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated && isTerminal($0)
        }
        for app in apps {
            if windowContainsPrompt(pid: app.processIdentifier) {
                return app.processIdentifier
            }
        }
        return nil
    }

    private func windowContainsPrompt(pid: pid_t) -> Bool {
        let axApp = AXUIElementCreateApplication(pid)
        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { return false }
        for window in windows {
            var buffer = ""
            collectText(from: window, into: &buffer, depth: 0)
            if matches(buffer) { return true }
        }
        return false
    }

    private func matches(_ text: String) -> Bool {
        let tail: String
        if text.count > tailSize {
            let start = text.index(text.endIndex, offsetBy: -tailSize)
            tail = String(text[start...])
        } else {
            tail = text
        }
        if !tail.contains(liveFooter) { return false }
        if !tail.contains(question) { return false }
        return yesMarkers.contains(where: { tail.contains($0) })
    }

    private func collectText(from element: AXUIElement, into out: inout String, depth: Int) {
        if depth > maxDepth { return }
        if out.count > textBudget { return }
        for attr in [kAXValueAttribute, kAXDescriptionAttribute, kAXTitleAttribute, kAXSelectedTextAttribute] {
            var v: AnyObject?
            if AXUIElementCopyAttributeValue(element, attr as CFString, &v) == .success,
               let s = v as? String, !s.isEmpty {
                out.append(s)
                out.append("\n")
                if out.count > textBudget { return }
            }
        }
        var children: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
           let arr = children as? [AXUIElement] {
            for child in arr {
                collectText(from: child, into: &out, depth: depth + 1)
                if out.count > textBudget { return }
            }
        }
    }

    /// Dump what the detector currently sees into a human-readable file,
    /// so the user can check whether accessibility is wired up and which
    /// terminal (if any) exposes its text through AX.
    func writeDiagnostic(to url: URL) throws {
        var out = "# dance-while-im-working diagnostic\n\n"
        out += "Accessibility trusted: \(AXIsProcessTrusted())\n"
        out += "Poll interval:         \(pollInterval)s\n"
        out += "Tail size:             \(tailSize) chars\n"
        out += "Required footer:       \"\(liveFooter)\"\n"
        out += "Required question:     \"\(question)\"\n"
        out += "Yes markers:           \(yesMarkers)\n\n"

        let regularApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated
        }
        let terminals = regularApps.filter(isTerminal)
        let skipped = regularApps.filter { !isTerminal($0) }
        out += "Regular apps running: \(regularApps.count)\n"
        out += "Terminals scanned:    \(terminals.count) — \(terminals.compactMap { $0.localizedName }.joined(separator: ", "))\n"
        out += "Skipped (non-terminal): \(skipped.count) — \(skipped.compactMap { $0.localizedName }.joined(separator: ", "))\n\n"

        for app in terminals {
            let name = app.localizedName ?? "?"
            let bundle = app.bundleIdentifier ?? "?"
            out += "── \(name)  [pid \(app.processIdentifier)]  \(bundle)\n"
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var windowsRef: AnyObject?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let windows = windowsRef as? [AXUIElement] else {
                out += "   (no AX windows exposed)\n\n"
                continue
            }
            out += "   \(windows.count) window(s)\n"
            for (i, window) in windows.enumerated() {
                var buffer = ""
                collectText(from: window, into: &buffer, depth: 0)
                let matched = matches(buffer)
                let tail: String
                if buffer.count > tailSize {
                    let start = buffer.index(buffer.endIndex, offsetBy: -tailSize)
                    tail = String(buffer[start...])
                } else {
                    tail = buffer
                }
                out += "   [window #\(i)] text=\(buffer.count) chars, matched=\(matched)\n"
                if !tail.isEmpty {
                    out += "   --- last \(tail.count) chars (the part we match against) ---\n"
                    out += tail
                    if !tail.hasSuffix("\n") { out += "\n" }
                    out += "   --- end ---\n"
                }
            }
            out += "\n"
        }

        try out.write(to: url, atomically: true, encoding: .utf8)
    }
}
