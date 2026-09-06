import AppKit
import Combine
import NotchFreeCore
import ServiceManagement

@MainActor final class ShelfStore: ObservableObject {
    @Published var items: [ShelfItem] = []
    @Published var busy = false
    @Published var error: String?
    var onImported: ((Int) -> Void)?
    private let queue = DispatchQueue(label: "NotchFree.shelf", qos: .userInitiated)
    private var repository: ShelfRepository?
    private var pending = 0
    init(root: URL) {
        do { repository = try ShelfRepository(root: root); items = repository?.items ?? [] }
        catch { self.error = error.localizedDescription }
    }
    func url(_ item: ShelfItem) -> URL? { try? repository?.fileURL(for: item) }
    func importFiles(_ urls: [URL], move: Bool = false) {
        guard let repository, !urls.isEmpty else { return }
        pending += 1; busy = true
        queue.async { [weak self] in
            var problems: [String] = [], count = 0
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do { try repository.add(url, move: move); count += 1 }
                catch { problems.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
            let items = repository.items
            Task { @MainActor in
                guard let self else { return }
                self.items = items; self.error = problems.isEmpty ? nil : problems.joined(separator: "\n")
                self.pending -= 1; self.busy = self.pending > 0
                if count > 0 { self.onImported?(count) }
            }
        }
    }
    func importText(_ text: String) {
        guard !text.isEmpty else { return }
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NotchFree-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let isLink = URL(string: text).map { ["http", "https"].contains($0.scheme?.lowercased() ?? "") } ?? false
            let file = directory.appendingPathComponent(isLink ? "Link.webloc" : "Text.txt")
            let data = isLink ? try PropertyListSerialization.data(fromPropertyList: ["URL": text], format: .xml, options: 0) : Data(text.utf8)
            try data.write(to: file, options: .atomic)
            importFiles([file])
            queue.async { try? FileManager.default.removeItem(at: directory) }
        } catch { self.error = error.localizedDescription }
    }
    func paste() {
        let board = NSPasteboard.general
        if let files = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !files.isEmpty { importFiles(files) }
        else if let text = board.string(forType: .string) { importText(text) }
    }
    func remove(_ item: ShelfItem) {
        guard let repository else { return }
        queue.async { [weak self] in
            do {
                try repository.remove(item) { file in try FileManager.default.trashItem(at: file, resultingItemURL: nil) }
                let items = repository.items
                Task { @MainActor in self?.items = items }
            } catch { Task { @MainActor in self?.error = error.localizedDescription } }
        }
    }
}

@MainActor final class ShareController: NSObject, NSSharingServiceDelegate {
    private var service: NSSharingService?
    var onEnd: (() -> Void)?
    var onError: ((String) -> Void)?
    func airDrop(_ items: [Any]) {
        guard !items.isEmpty, let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: items) else {
            onError?("AirDrop is unavailable for these items."); onEnd?(); return
        }
        self.service = service; service.delegate = self; service.perform(withItems: items)
    }
    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) { service = nil; onEnd?() }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        service = nil; onEnd?(); if (error as NSError).code != NSUserCancelledError { onError?(error.localizedDescription) }
    }
}

@MainActor final class AppModel: ObservableObject {
    static let identifier = "com.dsvyro.notchfree"
    static let dataRoot = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/NotchFree", isDirectory: true)
    @Published var presentation = Presentation()
    @Published var library = UserLibrary() { didSet { scheduleSave() } }
    @Published var now = Date()
    @Published var message: String?
    @Published var settingsRevision = 0
    @Published var selectedWidget: WidgetKind = .media
    let media = MediaProvider()
    let calendar = CalendarProvider()
    let camera = CameraProvider()
    let shortcuts = ShortcutProvider()
    let hud = SystemHUDProvider()
    let devices = DeviceActivities()
    let shelf = ShelfStore(root: dataRoot.appendingPathComponent("Tray"))
    let share = ShareController()
    private let disk = JSONDiskStore<UserLibrary>(url: dataRoot.appendingPathComponent("library.json"))
    private var canSave = false
    private var saveTask: Task<Void, Never>?
    private var clock: Timer?
    private var lastEvent = ""
    private var ticks = 0
    var showSettings: (() -> Void)?
    var requestPanel: (() -> Void)?
    var forcePanel: (() -> Void)?
    var allowHover: Bool { UserDefaults.standard.object(forKey: "openOnHover") as? Bool ?? true }
    var gestures: Bool { UserDefaults.standard.object(forKey: "gestures") as? Bool ?? true }
    var haptics: Bool { UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true }
    var panelWidth: CGFloat {
        let value = UserDefaults.standard.double(forKey: "panelWidth")
        return value > 0 ? min(900, max(600, value)) : 720
    }
    var allScreens: Bool { UserDefaults.standard.bool(forKey: "allScreens") }
    var hideFullscreen: Bool { UserDefaults.standard.object(forKey: "hideFullscreen") as? Bool ?? true }
    var activeScreenID: UInt32 { UInt32(max(0, UserDefaults.standard.integer(forKey: "screenID"))) }
    var activityEnabled: Bool { UserDefaults.standard.object(forKey: "activities") as? Bool ?? true }
    var startup: Bool { SMAppService.mainApp.status == .enabled }
    init() {
        do { library = try disk.load(default: UserLibrary()); canSave = true }
        catch { message = error.localizedDescription }
        selectedWidget = library.widgets.first ?? .media
        media.onTrackChanged = { [weak self] track in self?.show(Activity(title: track.title, subtitle: track.artist, symbol: "music.note", duration: 2.5)) }
        hud.onActivity = { [weak self] in self?.show($0) }
        devices.onActivity = { [weak self] in self?.show($0) }
        shelf.onImported = { [weak self] count in
            self?.feedback(); self?.show(Activity(title: "\(count) file\(count == 1 ? "" : "s") added", subtitle: "Ready in your tray", symbol: "tray.fill"))
        }
        share.onEnd = { [weak self] in self?.presentation.editing = false }
        share.onError = { [weak self] in self?.message = $0 }
        clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(clock!, forMode: .common)
        if library.timer.expire(now: Date()) { scheduleSave() }
    }
    func start() {
        media.start()
        if UserDefaults.standard.bool(forKey: "replaceHUD") { hud.enableKeyboard(request: false) }
        if UserDefaults.standard.bool(forKey: "bluetoothAlerts") { devices.enableBluetooth() }
    }
    private func tick() {
        now = Date(); presentation.tick(now: now); ticks += 1
        if library.timer.deadline != nil && library.timer.remaining(at: now) <= 0 {
            if library.timer.expire(now: now) { show(Activity(title: "Time’s up", subtitle: "Take a moment.", symbol: "timer", duration: 8)); NSSound.beep() }
        }
        if ticks % 30 == 0, let event = calendar.nextEvent(now: now), let id = event.eventIdentifier, id != lastEvent {
            lastEvent = id
            show(Activity(title: event.title ?? "Upcoming event", subtitle: "In \(max(1, Int(event.startDate.timeIntervalSince(now) / 60))) min", symbol: "calendar", duration: 5))
        }
    }
    func open(_ tab: PanelTab = .home) { presentation.open(tab); feedback(); requestPanel?() }
    func close(force: Bool = false) {
        presentation.close(force: force)
        if !presentation.expanded { camera.stop(); saveNow() }
    }
    func show(_ activity: Activity) { guard activityEnabled else { return }; presentation.show(activity) }
    func feedback() { if haptics { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) } }
    func selectWidget(_ widget: WidgetKind) {
        presentation.editing = false; if widget != .mirror { camera.stop() }
        selectedWidget = widget
        if widget == .shortcuts { shortcuts.refresh() }
    }
    func airDrop(_ items: [Any]) { presentation.editing = true; share.airDrop(items) }
    func toggleStartup(_ value: Bool) {
        do { if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; settingsRevision += 1 }
        catch { message = "Launch at login: \(error.localizedDescription)" }
    }
    func settingsChanged() { settingsRevision += 1; requestPanel?() }
    private func scheduleSave() {
        guard canSave else { return }; saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }; self?.saveNow()
        }
    }
    func saveNow() {
        guard canSave else { return }
        do { try disk.save(library) } catch { message = "Could not save: \(error.localizedDescription)" }
    }
    func stop() {
        clock?.invalidate(); saveTask?.cancel(); saveNow()
        camera.stop(); media.stop(); hud.stop(); devices.stop()
    }
}
