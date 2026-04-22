import AppKit
import CoreGraphics

enum KeyPresser {
    static func pressReturn() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let returnKey: CGKeyCode = 0x24
        let down = CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: false)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
