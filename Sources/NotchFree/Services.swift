import AppKit
import SwiftUI
@preconcurrency import AVFoundation
import EventKit
import Combine
import NotchFreeCore

enum CommandRunner {
    /// Argument arrays are passed directly to Process; user input never becomes shell code.
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 15) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process(), pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
                process.standardOutput = pipe; process.standardError = pipe
                do {
                    try process.run()
                    let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit(); watchdog.cancel()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    guard process.terminationStatus == 0 else {
                        throw NSError(domain: "Command", code: Int(process.terminationStatus),
                                      userInfo: [NSLocalizedDescriptionKey: String(output.prefix(500))])
                    }
                    continuation.resume(returning: output)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}

@MainActor final class MediaProvider: ObservableObject {
    enum Source: String, CaseIterable { case system = "Now Playing", music = "Apple Music", spotify = "Spotify" }
    @Published var snapshot = MediaSnapshot()
    @Published var source = Source(rawValue: UserDefaults.standard.string(forKey: "mediaSource") ?? "") ?? .system
    @Published var status = "Connecting to Now Playing…"
    var onTrackChanged: ((MediaSnapshot) -> Void)?
    private var process: Process?
    private var poll: Task<Void, Never>?
    private var generation = 0
    private var scriptURL: URL? { Bundle.main.resourceURL?.appendingPathComponent("mediaremote-adapter.pl") }
    private var frameworkURL: URL? { Bundle.main.privateFrameworksURL?.appendingPathComponent("MediaRemoteAdapter.framework") }
    func start() {
        stop(); generation += 1
        UserDefaults.standard.set(source.rawValue, forKey: "mediaSource")
        if source != .system { startFallback(); return }
        guard let scriptURL, let frameworkURL,
              FileManager.default.fileExists(atPath: frameworkURL.path) else {
            status = "Now Playing helper missing. Select Apple Music or Spotify."; return
        }
        let process = Process(), pipe = Pipe(), token = generation
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptURL.path, frameworkURL.path, "stream", "--no-diff", "--micros", "--debounce=100"]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        self.process = process
        do {
            try process.run(); status = "Connected to system Now Playing"
            DispatchQueue.global(qos: .utility).async { [weak self] in
                var buffer = Data()
                while true {
                    let data = pipe.fileHandleForReading.availableData
                    if data.isEmpty { break }
                    buffer.append(data)
                    while let newline = buffer.firstIndex(of: 10) {
                        let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
                        if let snapshot = try? MediaSnapshot.decode(line) {
                            Task { @MainActor [weak self] in
                                guard let self, self.generation == token else { return }
                                self.receive(snapshot)
                            }
                        }
                    }
                    if buffer.count > 16_000_000 { buffer.removeAll() }
                }
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    self.status = "Now Playing disconnected. Retry or select Apple Music / Spotify."
                    self.snapshot = MediaSnapshot()
                }
            }
        } catch { status = error.localizedDescription }
    }
    private func receive(_ value: MediaSnapshot) {
        let changed = value.available && value.title != snapshot.title
        snapshot = value
        if changed { onTrackChanged?(value) }
    }
    func stop() {
        generation += 1; poll?.cancel(); poll = nil
        if process?.isRunning == true { process?.terminate() }; process = nil
    }
    func send(_ command: Int) {
        if source == .system {
            helper(["send", String(command)])
        } else {
            let verb = [0: "play", 1: "pause", 2: "playpause", 4: "next track", 5: "previous track"][command] ?? "playpause"
            let id = source == .music ? "com.apple.Music" : "com.spotify.client"
            Task { do { _ = try await Self.appleScript("tell application id \"\(id)\" to \(verb)") }
                catch { status = "Allow Automation access in System Settings to control this player." } }
        }
    }
    func seek(_ seconds: Double) {
        guard seconds.isFinite, snapshot.duration > 0 else { return }
        let value = min(snapshot.duration, max(0, seconds))
        if source == .system { helper(["seek", String(Int64(value * 1_000_000))]) }
        else {
            let id = source == .music ? "com.apple.Music" : "com.spotify.client"
            Task { _ = try? await Self.appleScript("tell application id \"\(id)\" to set player position to \(value)") }
        }
    }
    private func helper(_ arguments: [String]) {
        guard let scriptURL, let frameworkURL else { return }
        Task { do { _ = try await CommandRunner.run("/usr/bin/perl", [scriptURL.path, frameworkURL.path] + arguments) }
            catch { status = "Media command failed: \(error.localizedDescription)" } }
    }
    private func startFallback() {
        status = "Automation access is needed for this player."
        let id = source == .music ? "com.apple.Music" : "com.spotify.client"
        poll = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty {
                    self.snapshot = MediaSnapshot(); self.status = "Open \(self.source.rawValue) to start listening."
                } else {
                    do {
                        let result = try await Self.appleScript("""
                        tell application id "\(id)"
                            if player state is stopped then return ""
                            set sep to ASCII character 31
                            return (name of current track as text) & sep & (artist of current track as text) & sep & (album of current track as text) & sep & (duration of current track as text) & sep & (player position as text) & sep & (player state as text)
                        end tell
                        """)
                        guard !Task.isCancelled else { return }
                        let fields = result.components(separatedBy: "\u{1f}")
                        if fields.count == 6 {
                            var item = MediaSnapshot()
                            item.title = fields[0]; item.artist = fields[1]; item.album = fields[2]; item.bundleID = id
                            item.duration = (Double(fields[3]) ?? 0) / (self.source == .spotify ? 1000 : 1)
                            item.elapsed = Double(fields[4]) ?? 0; item.playing = fields[5] == "playing"
                            item.timestamp = Date(); item.artwork = self.snapshot.title == item.title ? self.snapshot.artwork : nil
                            self.receive(item); self.status = "Connected to \(self.source.rawValue)"
                        } else { self.snapshot = MediaSnapshot() }
                    } catch { self.status = "Automation access unavailable. Enable it in System Settings." }
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }
    nonisolated static func appleScript(_ source: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                if let error { continuation.resume(throwing: NSError(domain: "Automation", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: error[NSAppleScript.errorMessage] as? String ?? "Automation failed"])) }
                else { continuation.resume(returning: result?.stringValue ?? "") }
            }
        }
    }
}

@MainActor final class CalendarProvider: ObservableObject {
    @Published var events: [EKEvent] = []
    @Published var selectedDay = Date()
    @Published var calendars: [EKCalendar] = []
    @Published var access = false
    @Published var status = "Connect your calendar"
    @Published var selectedIDs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "calendarIDs") ?? [])
    @Published var includeAllDay = UserDefaults.standard.object(forKey: "includeAllDay") as? Bool ?? true
    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    init() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }
    func requestAccess() {
        Task {
            do { access = try await store.requestFullAccessToEvents(); refresh() }
            catch { status = error.localizedDescription }
        }
    }
    func refresh() {
        access = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        guard access else { events = []; status = "Calendar access is off"; return }
        calendars = store.calendars(for: .event)
        let available = Set(calendars.map(\.calendarIdentifier))
        selectedIDs.formIntersection(available)
        let explicitlySelected = UserDefaults.standard.bool(forKey: "calendarSelectionConfigured")
        let visible = !explicitlySelected ? calendars : calendars.filter { selectedIDs.contains($0.calendarIdentifier) }
        let start = Calendar.current.startOfDay(for: selectedDay)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        events = visible.isEmpty ? [] : store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: visible))
            .filter { includeAllDay || !$0.isAllDay }.sorted { $0.startDate < $1.startDate }
        status = events.isEmpty ? "A little room to breathe." : "\(events.count) event\(events.count == 1 ? "" : "s")"
    }
    func saveSelection() {
        UserDefaults.standard.set(true, forKey: "calendarSelectionConfigured")
        UserDefaults.standard.set(Array(selectedIDs), forKey: "calendarIDs")
        UserDefaults.standard.set(includeAllDay, forKey: "includeAllDay"); refresh()
    }
    func nextEvent(now: Date) -> EKEvent? {
        guard access else { return nil }
        let selected = UserDefaults.standard.bool(forKey: "calendarSelectionConfigured") ? calendars.filter { selectedIDs.contains($0.calendarIdentifier) } : calendars
        guard !selected.isEmpty else { return nil }
        return store.events(matching: store.predicateForEvents(withStart: now, end: now.addingTimeInterval(300), calendars: selected))
            .filter { !$0.isAllDay && $0.startDate >= now }.min { $0.startDate < $1.startDate }
    }
}

@MainActor final class CameraProvider: ObservableObject {
    let session = AVCaptureSession()
    @Published var active = false
    @Published var devices: [AVCaptureDevice] = []
    @Published var selectedID = ""
    @Published var status = "A quick look before your next call."
    private let queue = DispatchQueue(label: "NotchFree.camera")
    private var requestGeneration = 0
    func start() {
        requestGeneration += 1; let generation = requestGeneration
        Task {
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            guard generation == requestGeneration else { return }
            guard allowed else { status = "Enable Camera access in System Settings."; return }
            devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera], mediaType: .video, position: .unspecified).devices
            guard let device = devices.first(where: { $0.uniqueID == selectedID }) ?? devices.first else {
                status = "No camera connected."; return
            }
            selectedID = device.uniqueID
            let session = self.session
            queue.async {
                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    session.beginConfiguration(); session.inputs.forEach { session.removeInput($0) }
                    session.sessionPreset = .medium
                    if session.canAddInput(input) { session.addInput(input) }
                    session.commitConfiguration(); session.startRunning()
                    Task { @MainActor [weak self] in
                        guard let self, self.requestGeneration == generation else { return }
                        self.active = session.isRunning; self.status = session.isRunning ? "Camera is on" : "Camera could not start"
                    }
                } catch { Task { @MainActor [weak self] in self?.status = error.localizedDescription } }
            }
        }
    }
    func stop() {
        requestGeneration += 1; active = false
        let session = self.session; queue.async { session.stopRunning() }
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> PreviewView { PreviewView(session: session) }
    func updateNSView(_ nsView: PreviewView, context: Context) {}
    final class PreviewView: NSView {
        let preview: AVCaptureVideoPreviewLayer
        init(session: AVCaptureSession) {
            preview = AVCaptureVideoPreviewLayer(session: session)
            super.init(frame: .zero); wantsLayer = true
            preview.videoGravity = .resizeAspectFill; layer?.addSublayer(preview)
            if let connection = preview.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = true
            }
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func layout() { super.layout(); preview.frame = bounds }
    }
}

@MainActor final class ShortcutProvider: ObservableObject {
    @Published var names: [String] = []
    @Published var running: String?
    @Published var status = ""
    func refresh() {
        Task { do {
            names = try await CommandRunner.run("/usr/bin/shortcuts", ["list"]).split(separator: "\n").map(String.init).sorted()
            status = names.isEmpty ? "Create a shortcut in the Shortcuts app." : ""
        } catch { status = "Could not load Shortcuts. Open the Shortcuts app and retry." } }
    }
    func run(_ name: String) {
        guard running == nil else { return }; running = name
        Task { defer { running = nil }
            do { _ = try await CommandRunner.run("/usr/bin/shortcuts", ["run", name], timeout: 120); status = "Finished" }
            catch { status = "Shortcut failed or timed out." }
        }
    }
}
