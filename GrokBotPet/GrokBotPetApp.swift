import AppKit
import SwiftUI

@main
enum GrokBotPetApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = PetAppDelegate()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
private final class PetAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let defaults = UserDefaults.standard
    private lazy var style = BotStyle.load(from: defaults)
    private lazy var pet = LumoView(style: style)
    private lazy var panel = makePanel()
    private lazy var customizer = makeCustomizer()
    private lazy var activityMonitor = TaskActivityMonitor(defaults: defaults) { [weak self] _ in
        self?.updateTaskBubble()
    }
    private var taskBubble: TaskBubble?
    private lazy var positionItem = menuItem("Move Lumo", action: #selector(togglePositionLock))
    private lazy var activityItem = menuItem("Connect Task Activity…", action: #selector(toggleActivityConnection))

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu(title: "Lumo")
        menu.addItem(menuItem("Customize Lumo…", action: #selector(showCustomizer)))
        menu.addItem(activityItem)
        menu.addItem(.separator())
        menu.addItem(menuItem("Hide Lumo", action: #selector(hidePet)))
        menu.addItem(positionItem)
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Lumo", action: #selector(quit)))
        pet.menu = menu

        showPet()
        activityMonitor.restore()
        updateActivityMenu()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !panel.isVisible { showPet() }
        return false
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        keepPanelOnScreen()
        updateTaskBubble()
    }

    func windowDidMove(_ notification: Notification) {
        updateTaskBubble()
    }

    @objc private func toggleActivityConnection() {
        if activityMonitor.isConnected {
            activityMonitor.disconnect()
        } else {
            let picker = NSOpenPanel()
            picker.canChooseFiles = false
            picker.canChooseDirectories = true
            picker.allowsMultipleSelection = false
            picker.prompt = "Connect"
            picker.message = "Choose the Activity folder created by Lumo’s hook setup."
            picker.directoryURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Lumo/Activity", isDirectory: true)
            NSApp.activate()
            guard picker.runModal() == .OK, let folder = picker.url else { return }
            do {
                try activityMonitor.connect(to: folder)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Couldn’t connect to task activity"
                alert.informativeText = "Run Lumo’s hook setup and select the Activity folder it prints."
                alert.runModal()
            }
        }
        updateActivityMenu()
    }

    private func updateActivityMenu() {
        activityItem.title = activityMonitor.isConnected ? "Disconnect Task Activity" : "Connect Task Activity…"
    }

    private func updateTaskBubble() {
        guard panel.isVisible, let activity = activityMonitor.current else {
            taskBubble?.hide()
            return
        }
        if taskBubble == nil { taskBubble = TaskBubble() }
        taskBubble?.show(activity, beside: panel)
    }

    private func makeCustomizer() -> NSWindow {
        let editor = BotCustomizer(
            style: style,
            onChange: { [weak self] in self?.applyStyle($0) },
            onClose: { [weak self] in self?.customizer.close() }
        )
        let window = NSWindow(contentViewController: NSHostingController(rootView: editor))
        window.styleMask = [.titled, .closable]
        window.title = "Customize Lumo"
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    @objc private func showCustomizer() {
        NSApp.activate()
        customizer.makeKeyAndOrderFront(nil)
    }

    private func applyStyle(_ newStyle: BotStyle) {
        style = newStyle
        style.save(to: defaults)
        pet.setStyle(style)
    }

    private func makePanel() -> NSPanel {
        var frame = pet.frame
        if let screen = NSScreen.main {
            frame.origin = defaultOrigin(for: frame.size, on: screen)
        }
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Lumo"
        panel.contentView = pet
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = true
        panel.setFrameUsingName("Lumo")
        panel.setFrameAutosaveName("Lumo")
        panel.delegate = self
        return panel
    }

    private func defaultOrigin(for size: NSSize, on screen: NSScreen) -> NSPoint {
        let visible = screen.visibleFrame
        return NSPoint(x: visible.maxX - size.width - 12, y: visible.minY + 12)
    }

    private func keepPanelOnScreen() {
        guard !NSScreen.screens.contains(where: { $0.visibleFrame.contains(panel.frame) }),
              let screen = NSScreen.main else {
            return
        }
        panel.setFrameOrigin(defaultOrigin(for: panel.frame.size, on: screen))
    }

    private func showPet() {
        keepPanelOnScreen()
        panel.orderFrontRegardless()
        pet.startTracking()
        updateTaskBubble()
    }

    @objc private func hidePet() {
        pet.stopTracking()
        panel.orderOut(nil)
        taskBubble?.hide()
        setPositionLocked(true)
    }

    @objc private func togglePositionLock() {
        setPositionLocked(!pet.isPositionLocked)
    }

    private func setPositionLocked(_ locked: Bool) {
        pet.isPositionLocked = locked
        positionItem.title = locked ? "Move Lumo" : "Lock Position"
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }
}
