import AppKit
import ApplicationServices

final class PromptDetector {
    private let state: AppState
    private var timer: Timer?

    private let pollInterval: TimeInterval = 0.5
    private let autoPressCooldown: TimeInterval = 3.0
    private let maxDepth = 40
    private let textBudget = 32_000

    /// Phrases that identify a Claude Code permission prompt.
    /// We match on the question *and* the numbered-option list together
    /// to avoid firing on plain shell output that just happens to contain
    /// "Yes" or question marks.
    private let requiredAll: [String] = [
        "Do you want to proceed?"
    ]
    private let requiredAny: [String] = [
        "1. Yes",
        "❯ 1. Yes"
    ]

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
            $0.activationPolicy == .regular && !$0.isTerminated
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
        for needle in requiredAll where !text.contains(needle) { return false }
        for needle in requiredAny where text.contains(needle) { return true }
        return false
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
}
