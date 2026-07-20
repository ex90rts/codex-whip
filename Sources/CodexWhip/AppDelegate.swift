import AppKit
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var coordinator: ReactionCoordinator?
    private var hoverMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = ReactionCoordinator()
        self.coordinator = coordinator
        configureStatusMenu()
        coordinator.showWelcome()
        requestFeedbackAccessibilityTrustIfNeeded()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(receiveTaskCompletion),
            name: .codexWhipTaskCompleted,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "codexwhip" {
            switch url.host {
            case "task-completed":
                coordinator?.showRatingPrompt()
            case "play-whip":
                coordinator?.play(.whip)
            case "play-praise":
                coordinator?.play(.praise)
            default:
                continue
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator?.showWelcome()
        return true
    }

    @objc private func receiveTaskCompletion(_ notification: Notification) {
        coordinator?.showRatingPrompt()
    }

    @objc private func simulateTaskCompletion() {
        coordinator?.showRatingPrompt()
    }

    @objc private func playPraise() {
        coordinator?.play(.praise)
    }

    @objc private func playWhip() {
        coordinator?.play(.whip)
    }

    @objc private func toggleHover() {
        guard let coordinator else { return }
        coordinator.isMouseHoverEnabled.toggle()
        hoverMenuItem?.state = coordinator.isMouseHoverEnabled ? .on : .off
    }

    @objc private func requestFeedbackAccessibilityTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func configureStatusMenu() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "wand.and.sparkles",
            accessibilityDescription: "Codex Whip"
        )
        statusItem.button?.toolTip = "Codex Whip"

        let menu = NSMenu()
        menu.addItem(menuItem("检测宠物并显示评价", action: #selector(simulateTaskCompletion), key: "r"))
        menu.addItem(.separator())
        menu.addItem(menuItem("试播：摸头", action: #selector(playPraise)))
        menu.addItem(menuItem("试播：抽三鞭", action: #selector(playWhip)))

        let hoverItem = menuItem("抚摸前真实鼠标 Hover（短暂移动光标）", action: #selector(toggleHover))
        hoverItem.state = coordinator?.isMouseHoverEnabled == true ? .on : .off
        menu.addItem(hoverItem)
        hoverMenuItem = hoverItem

        menu.addItem(menuItem("启用宠物反馈权限…", action: #selector(requestFeedbackAccessibilityTrust)))

        menu.addItem(.separator())
        menu.addItem(menuItem("退出 Codex Whip", action: #selector(quit), key: "q"))
        statusItem.menu = menu
        self.statusItem = statusItem
    }

    private func menuItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func requestFeedbackAccessibilityTrustIfNeeded() {
        // An ad-hoc-signed development build can become a new TCC identity
        // after rebuilding. Always ask macOS again while this exact build is
        // untrusted; macOS itself suppresses duplicate system prompts.
        guard !AXIsProcessTrusted() else { return }
        requestFeedbackAccessibilityTrust()
    }
}

extension Notification.Name {
    static let codexWhipTaskCompleted = Notification.Name("com.codexwhip.taskCompleted")
}
