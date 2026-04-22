import AppKit
import ApplicationServices

final class PromptDetector {
    private let state: AppState
    private var timer: Timer?
    private var lastMatch = false

    private let pollInterval: TimeInterval = 0.5
    private let autoPressCooldown: TimeInterval = 2.0
    private let maxDepth = 40

    private let signals = [
        "Do you want to proceed?",
        "1. Yes",
        "❯ 1. Yes"
    ]

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
            lastMatch = false
            return
        }
        let match = detectPrompt()
        if match != lastMatch {
            lastMatch = match
            state.isDancing = match
        }
        if match && state.autoPressEnter {
            let now = Date()
            if let last = state.lastAutoPressAt, now.timeIntervalSince(last) < autoPressCooldown {
                return
            }
            state.lastAutoPressAt = now
            KeyPresser.pressReturn()
        }
    }

    private func detectPrompt() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }
        let axApp = AXUIElementCreateApplication(frontApp.processIdentifier)
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focused) == .success,
              let window = focused else { return false }
        var buffer = ""
        collectText(from: window as! AXUIElement, into: &buffer, depth: 0, budget: 32_000)
        for signal in signals where buffer.contains(signal) {
            return true
        }
        return false
    }

    private func collectText(from element: AXUIElement, into out: inout String, depth: Int, budget: Int) {
        if depth > maxDepth { return }
        if out.count > budget { return }
        for attr in [kAXValueAttribute, kAXDescriptionAttribute, kAXTitleAttribute, kAXSelectedTextAttribute] {
            var v: AnyObject?
            if AXUIElementCopyAttributeValue(element, attr as CFString, &v) == .success,
               let s = v as? String, !s.isEmpty {
                out.append(s)
                out.append("\n")
                if out.count > budget { return }
            }
        }
        var children: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
           let arr = children as? [AXUIElement] {
            for child in arr {
                collectText(from: child, into: &out, depth: depth + 1, budget: budget)
                if out.count > budget { return }
            }
        }
    }
}
