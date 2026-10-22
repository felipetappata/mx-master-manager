import AppKit
import SwiftUI

@main
enum MXMasterManagerApp {
    static func main() {
        if CommandLine.arguments.contains("--delayed-start") { Thread.sleep(forTimeInterval: 1) }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = ManagerModel()
    private var window: NSWindow?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let existing = others.first, !CommandLine.arguments.contains("--delayed-start") {
            existing.activate(options: [.activateIgnoringOtherApps])
            NSApplication.shared.terminate(nil)
            return
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "MX Master Manager…", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit MX Master Manager", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items { item.target = self }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "MX Master Manager")
        statusItem?.menu = menu
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem()
        applicationItem.submenu = menu.copy() as? NSMenu
        mainMenu.addItem(applicationItem)
        NSApplication.shared.mainMenu = mainMenu
        model.start()
        if !CommandLine.arguments.contains("--background") { showSettings() }
    }

    @objc func showSettings() {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(model: model))
            let result = NSWindow(contentViewController: controller)
            result.title = "MX Master Manager"
            result.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            result.setContentSize(NSSize(width: 1120, height: 720))
            result.minSize = NSSize(width: 1000, height: 640)
            result.isReleasedWhenClosed = false
            result.center()
            window = result
        }
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) { model.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    @objc func quit() { NSApplication.shared.terminate(nil) }
}
