import AppKit
import Combine

final class MenuBarController: NSObject {
    private let state: AppState
    private let statusItem: NSStatusItem
    private var cancellables = Set<AnyCancellable>()

    private var animationTimer: Timer?
    private var frameIndex = 0
    private let danceFrames = ["figure.dance", "figure.socialdance"]
    private let sleepFrame = "moon.zzz.fill"

    private weak var autoPressItem: NSMenuItem?
    private weak var pauseItem: NSMenuItem?

    /// Injected so the "Run diagnostic…" menu item can trigger a snapshot dump.
    var diagnosticProvider: (() -> PromptDetector?)?

    init(state: AppState) {
        self.state = state
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        buildMenu()
        render()
        bind()
    }

    private func buildMenu() {
        let menu = NSMenu()

        let auto = NSMenuItem(title: "Auto-press Enter", action: #selector(toggleAutoPress), keyEquivalent: "")
        auto.target = self
        auto.state = state.autoPressEnter ? .on : .off
        menu.addItem(auto)
        autoPressItem = auto

        let pause = NSMenuItem(title: "Pause detection", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        pause.state = state.paused ? .on : .off
        menu.addItem(pause)
        pauseItem = pause

        menu.addItem(.separator())

        let ax = NSMenuItem(title: "Open Accessibility Settings…", action: #selector(openAccessibility), keyEquivalent: "")
        ax.target = self
        menu.addItem(ax)

        let diag = NSMenuItem(title: "Run diagnostic…", action: #selector(runDiagnostic), keyEquivalent: "")
        diag.target = self
        menu.addItem(diag)

        let about = NSMenuItem(title: "About dance-while-im-working", action: #selector(openRepo), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func bind() {
        state.$isDancing
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.render() }
            .store(in: &cancellables)
        state.$paused
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.render()
                self?.pauseItem?.state = self?.state.paused == true ? .on : .off
            }
            .store(in: &cancellables)
        state.$autoPressEnter
            .receive(on: RunLoop.main)
            .sink { [weak self] v in
                self?.autoPressItem?.state = v ? .on : .off
            }
            .store(in: &cancellables)
    }

    private func render() {
        let shouldDance = state.isDancing && !state.paused
        if shouldDance { startAnimating() } else { stopAnimating(showSleep: true) }
    }

    private func startAnimating() {
        if animationTimer != nil { return }
        frameIndex = 0
        setSymbol(danceFrames[frameIndex], label: "Claude is dancing — waiting for you")
        let t = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.frameIndex = (self.frameIndex + 1) % self.danceFrames.count
            self.setSymbol(self.danceFrames[self.frameIndex], label: "Claude is dancing")
        }
        RunLoop.main.add(t, forMode: .common)
        animationTimer = t
    }

    private func stopAnimating(showSleep: Bool) {
        animationTimer?.invalidate()
        animationTimer = nil
        if showSleep {
            setSymbol(sleepFrame, label: "Claude is sleeping")
        }
    }

    private func setSymbol(_ name: String, label: String) {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: label)
            ?? NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: label)
        image?.isTemplate = true
        button.image = image
        button.toolTip = label
    }

    @objc private func toggleAutoPress() { state.autoPressEnter.toggle() }
    @objc private func togglePause() { state.paused.toggle() }

    @objc private func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openRepo() {
        if let url = URL(string: "https://github.com/Chad-Mufasax/dance-while-im-working") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func runDiagnostic() {
        guard let detector = diagnosticProvider?() else { return }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/dance-diag.txt")
        do {
            try detector.writeDiagnostic(to: url)
            NSWorkspace.shared.open(url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Diagnostic failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}
