import AppKit
import CoreGraphics

enum KeyPresser {
    /// Deliver a Return keystroke to a specific process only.
    /// Uses `postToPid` so the event reaches the target terminal regardless of focus,
    /// and never lands in whatever window the user is actually typing in.
    static func pressReturn(pid: pid_t) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let returnKey: CGKeyCode = 0x24
        let down = CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: false)
        down?.postToPid(pid)
        up?.postToPid(pid)
    }
}
