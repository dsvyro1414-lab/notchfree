import AppKit
import SwiftUI
import Combine
import NotchFreeCore
import Quartz

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct ScreenGeometry {
    var width: CGFloat
    var height: CGFloat
    var center: CGFloat
    var hasPhysicalNotch: Bool
    init(_ screen: NSScreen) {
        height = max(26, screen.safeAreaInsets.top)
        if screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            hasPhysicalNotch = true
            width = right.minX - left.maxX; center = (left.maxX + right.minX) / 2
        } else { hasPhysicalNotch = false; width = 180; center = screen.frame.midX }
    }
}

extension AppModel {
    var showsMiniPlayer: Bool { library.widgets.contains(.media) }
    var hasCompactContent: Bool {
        showsMiniPlayer || media.snapshot.available || library.timer.isRunning || !shelf.items.isEmpty
    }
    func panelSize(geometry: ScreenGeometry, availableWidth: CGFloat) -> PanelSize {
        PanelMetrics.visibleSize(notchWidth: geometry.width, notchHeight: geometry.height,
                                 panelWidth: panelWidth, availableWidth: min(panelWidth, availableWidth),
                                 expanded: presentation.expanded, activity: presentation.visibleActivity != nil,
                                 compact: hasCompactContent,
                                 message: message != nil, trayError: presentation.tab == .tray && shelf.error != nil)
    }
}

@MainActor final class PanelController {
    let model: AppModel
    private var panels: [(NSScreen, NotchPanel)] = []
    private var subscriptions = Set<AnyCancellable>()
    private var monitors: [Any] = []
    private var hoverTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?
    private var tick: Timer?
    private var fullscreenScreens = Set<UInt32>()
    private var inside = false
    init(model: AppModel) {
        self.model = model
        rebuild()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.rebuild() }
        }
        model.$settingsRevision.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.rebuild() } }.store(in: &subscriptions)
        model.$presentation.sink { [weak self] _ in DispatchQueue.main.async { self?.updateMouse() } }.store(in: &subscriptions)
        model.$message.sink { [weak self] _ in DispatchQueue.main.async { self?.updateMouse() } }.store(in: &subscriptions)
        model.shelf.$error.sink { [weak self] _ in DispatchQueue.main.async { self?.updateMouse() } }.store(in: &subscriptions)
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseDown], handler: { [weak self] _ in self?.updateMouse() }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .keyDown], handler: { [weak self] event in
            guard let self else { return event }; self.updateMouse()
            if event.type == .keyDown, event.keyCode == 53, self.panels.contains(where: { $0.1.isKeyWindow }) {
                if self.model.selectedWidget == .timer, self.model.presentation.editing { return event }
                self.model.close(force: true); NSApp.keyWindow?.resignKey(); return nil
            }
            return event
        }) { monitors.append(monitor) }
        tick = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkFullscreen(); self?.updateMouse() }
        }
        model.requestPanel = { [weak self] in self?.updateMouse() }
        model.forcePanel = { [weak self] in self?.openFromMenu() }
    }
    func rebuild() {
        panels.forEach { $0.1.close() }; panels.removeAll()
        var screens = NSScreen.screens
        if !model.allScreens {
            let preferred = screens.first { $0.displayID == model.activeScreenID }
                ?? screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? screens.first
            screens = preferred.map { [$0] } ?? []
        }
        for screen in screens {
            let geometry = ScreenGeometry(screen)
            let envelope = min(model.panelWidth + PanelMetrics.shadowGutter, screen.frame.width)
            let envelopeHeight = PanelMetrics.envelopeHeight(notchHeight: geometry.height)
            let frame = NSRect(x: geometry.center - envelope / 2, y: screen.frame.maxY - envelopeHeight, width: envelope, height: envelopeHeight)
            let panel = NotchPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.isMovable = false; panel.hidesOnDeactivate = false; panel.acceptsMouseMovedEvents = true
            panel.isReleasedWhenClosed = false; panel.title = "NotchFree"
            panel.contentView = DropHostingView(rootView: AnyView(NotchRootView(model: model, geometry: geometry, availableWidth: envelope)
                .modifier(AccentTheme(appearance: model.appearance))), model: model)
            panel.orderFrontRegardless(); panels.append((screen, panel))
        }
        updateMouse()
    }
    private func visibleRect(_ screen: NSScreen) -> NSRect {
        let geometry = ScreenGeometry(screen)
        let size = model.panelSize(geometry: geometry, availableWidth: screen.frame.width - PanelMetrics.shadowGutter)
        return NSRect(x: geometry.center - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
    }
    func openFromMenu() {
        model.open(); panels.first?.1.orderFrontRegardless(); panels.first?.1.makeKey()
    }
    private func updateMouse() {
        let mouse = NSEvent.mouseLocation
        var within = false
        for (screen, panel) in panels {
            let rect = visibleRect(screen)
            let hit = rect.insetBy(dx: -3, dy: -5).contains(mouse)
            within = within || hit
            panel.ignoresMouseEvents = !hit
            let hidden = model.hideFullscreen && fullscreenScreens.contains(screen.displayID) && !hit && !model.presentation.expanded
            if hidden { panel.orderOut(nil) } else if !panel.isVisible { panel.orderFrontRegardless() }
        }
        if within && !inside {
            closeTask?.cancel(); hoverTask?.cancel()
            if model.allowHover && !model.presentation.expanded {
                hoverTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 140_000_000)
                    guard !Task.isCancelled else { return }; self?.model.open()
                }
            }
        } else if !within && inside {
            hoverTask?.cancel(); closeTask?.cancel()
            closeTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                self?.model.close()
                if self?.model.presentation.expanded == false { self?.panels.forEach { $0.1.resignKey() } }
            }
        }
        inside = within
    }
    private func checkFullscreen() {
        guard model.hideFullscreen,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return }
        fullscreenScreens.removeAll()
        for (screen, _) in panels {
            let bounds = CGDisplayBounds(screen.displayID)
            let fullscreen = windows.contains { item in
                guard item[kCGWindowLayer as String] as? Int == 0,
                      let owner = item[kCGWindowOwnerPID as String] as? Int,
                      owner != Int(ProcessInfo.processInfo.processIdentifier),
                      let raw = item[kCGWindowBounds as String] as? [String: Any],
                      let rect = CGRect(dictionaryRepresentation: raw as CFDictionary) else { return false }
                return abs(rect.minX - bounds.minX) < 2 && abs(rect.minY - bounds.minY) < 2 && rect.width >= bounds.width - 2 && rect.height >= bounds.height - 2
            }
            if fullscreen { fullscreenScreens.insert(screen.displayID) }
        }
    }
    func stop() {
        hoverTask?.cancel(); closeTask?.cancel(); tick?.invalidate()
        monitors.forEach(NSEvent.removeMonitor)
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        panels.forEach { $0.1.close() }
    }
}

@MainActor final class DropHostingView: NSHostingView<AnyView> {
    let model: AppModel
    private var scrollAccumulation: CGFloat = 0
    private var lastScroll = Date.distantPast
    init(rootView: AnyView, model: AppModel) {
        self.model = model; super.init(rootView: rootView)
        let promises: [NSPasteboard.PasteboardType] = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        registerForDraggedTypes([.fileURL, .URL, .string] + promises)
    }
    required init(rootView: AnyView) { fatalError("Use init(rootView:model:)") }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        model.presentation.dragging = true; model.open(.tray)
        return sender.draggingSourceOperationMask.contains(.copy) ? .copy : .move
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        NSEvent.modifierFlags.contains(.option) && sender.draggingSourceOperationMask.contains(.move) ? .move : .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { model.presentation.dragging = false }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { model.presentation.dragging = false }
        let board = sender.draggingPasteboard
        if let receivers = board.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver], !receivers.isEmpty {
            for receiver in receivers {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NotchFree-Promise-" + UUID().uuidString)
                do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
                catch { model.message = AppFailure.message(error, operation: .importFile); return false }
                receiver.receivePromisedFiles(atDestination: directory, options: [:], operationQueue: OperationQueue()) { [weak model] url, error in
                    Task { @MainActor in
                        if let error { model?.message = AppFailure.message(error, operation: .importFile) }
                        else { model?.shelf.importFiles([url], move: true) }
                    }
                }
            }
            return true
        }
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            let move = NSEvent.modifierFlags.contains(.option) && sender.draggingSourceOperationMask.contains(.move)
            model.shelf.importFiles(urls, move: move); return true
        }
        if let text = board.string(forType: .URL) ?? board.string(forType: .string) { model.shelf.importText(text); return true }
        return false
    }
    override func scrollWheel(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // Gestures belong to the top strip; widget scroll views retain their normal scrolling.
        let distanceFromTop = isFlipped ? point.y : bounds.height - point.y
        guard model.gestures, distanceFromTop >= 0, distanceFromTop < 40 else { super.scrollWheel(with: event); return }
        if Date().timeIntervalSince(lastScroll) > 0.35 { scrollAccumulation = 0 }
        lastScroll = Date(); scrollAccumulation += event.scrollingDeltaY
        if abs(scrollAccumulation) > 18 {
            if scrollAccumulation < 0 { model.open() } else { model.close(force: true) }
            scrollAccumulation = 0
        }
        if abs(event.scrollingDeltaX) > 14 {
            if model.presentation.expanded { model.open(model.presentation.tab == .home ? .tray : .home) }
            else { model.media.send(event.scrollingDeltaX > 0 ? 5 : 4) }
        }
    }
}

@MainActor final class QuickLookController: NSObject, @preconcurrency QLPreviewPanelDataSource {
    static let shared = QuickLookController()
    private var urls: [URL] = []
    func show(_ urls: [URL]) {
        guard !urls.isEmpty else { return }; self.urls = urls
        let panel = QLPreviewPanel.shared()!; panel.dataSource = self; panel.reloadData(); panel.makeKeyAndOrderFront(nil)
    }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { urls[index] as NSURL }
}
