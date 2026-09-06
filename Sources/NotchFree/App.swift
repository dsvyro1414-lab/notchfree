import AppKit
import SwiftUI
import os

@main enum NotchFreeMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var panelController: PanelController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private let logger = Logger(subsystem: AppModel.identifier, category: "App")
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: AppModel.identifier).count <= 1 else { NSApp.terminate(nil); return }
        model = AppModel(); panelController = PanelController(model: model)
        model.showSettings = { [weak self] in self?.showSettings() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "NotchFree")
        let menu = NSMenu()
        menu.addItem(withTitle: "Open NotchFree", action: #selector(openPanel), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit NotchFree", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }; statusItem?.menu = menu
        let applicationMenu = NSMenu(); applicationMenu.addItem(withTitle: "NotchFree", action: nil, keyEquivalent: "").submenu = menu.copy() as? NSMenu
        let edit = NSMenu(title: "Edit")
        for (title, selector, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }
        applicationMenu.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit; NSApp.mainMenu = applicationMenu
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.model.camera.stop(); self?.model.media.stop(); self?.model.saveNow() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.model.media.start(); self?.model.calendar.refresh(); self?.model.devices.updatePower(); self?.panelController?.rebuild() }
        })
        model.start(); logger.info("NotchFree launched; source alpha")
        if !UserDefaults.standard.bool(forKey: "onboarded") { showSettings() }
    }
    @objc func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 610), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "NotchFree"; window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
            window.backgroundColor = NSColor(white: 0.065, alpha: 1); window.appearance = NSAppearance(named: .darkAqua)
            window.isReleasedWhenClosed = false; window.minSize = NSSize(width: 730, height: 570)
            window.contentView = NSHostingView(rootView: SettingsView(model: model, appearance: model.appearance)
                .modifier(AccentTheme(appearance: model.appearance))); window.center(); settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc func openPanel() { panelController?.openFromMenu() }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        model?.stop(); panelController?.stop()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
}
