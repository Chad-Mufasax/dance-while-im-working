import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private var menuBar: MenuBarController!
    private var detector: PromptDetector!

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController(state: state)
        detector = PromptDetector(state: state)
        menuBar.diagnosticProvider = { [weak self] in self?.detector }
        detector.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        detector?.stop()
    }
}
