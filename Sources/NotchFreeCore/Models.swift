import Foundation

public enum PanelTab: String, Codable, CaseIterable, Sendable { case home, tray }
public enum WidgetKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case media, calendar, timer, notes, tasks, shortcuts, mirror
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public struct Activity: Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var subtitle: String
    public var symbol: String
    public var level: Double?
    public var expiresAt: Date
    public init(title: String, subtitle: String = "", symbol: String, level: Double? = nil,
                duration: TimeInterval = 3, now: Date = Date()) {
        self.id = UUID(); self.title = title; self.subtitle = subtitle
        self.symbol = symbol; self.level = level; self.expiresAt = now.addingTimeInterval(duration)
    }
}

/// One reducer owns transient vs. interactive presentation. HUDs never replace an editor.
public struct Presentation: Sendable {
    public var expanded = false
    public var tab: PanelTab = .home
    public var editing = false
    public var dragging = false
    public var activity: Activity?
    public init() {}
    public mutating func open(_ tab: PanelTab = .home) { self.tab = tab; expanded = true }
    public mutating func close(force: Bool = false) {
        guard force || (!editing && !dragging) else { return }
        expanded = false; editing = false; dragging = false
    }
    public mutating func show(_ activity: Activity) { self.activity = activity }
    public mutating func tick(now: Date) {
        if let activity, activity.expiresAt <= now { self.activity = nil }
    }
    public var visibleActivity: Activity? { expanded || editing || dragging ? nil : activity }
}

public struct Countdown: Codable, Equatable, Sendable {
    public var deadline: Date?
    public var pausedRemaining: TimeInterval?
    public var duration: TimeInterval = 300
    public var completed = false
    public init() {}
    public var isRunning: Bool { deadline != nil }
    public func remaining(at now: Date) -> TimeInterval {
        max(0, deadline.map { $0.timeIntervalSince(now) } ?? pausedRemaining ?? duration)
    }
    public mutating func start(seconds: TimeInterval, now: Date) {
        duration = max(1, seconds); deadline = now.addingTimeInterval(duration)
        pausedRemaining = nil; completed = false
    }
    public mutating func pause(now: Date) { pausedRemaining = remaining(at: now); deadline = nil }
    public mutating func resume(now: Date) {
        guard let pausedRemaining else { return }
        deadline = now.addingTimeInterval(pausedRemaining); self.pausedRemaining = nil
    }
    @discardableResult public mutating func expire(now: Date) -> Bool {
        guard let deadline, deadline <= now else { return false }
        self.deadline = nil; pausedRemaining = 0; completed = true; return true
    }
    public mutating func reset() { deadline = nil; pausedRemaining = nil; completed = false }
}

public struct Todo: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var text: String
    public var favorite = false
    public var completedAt: Date?
    public init(text: String) { self.text = text }
}
public struct UserLibrary: Codable, Sendable {
    public var version = 1
    public var note = ""
    public var todos: [Todo] = []
    public var timer = Countdown()
    public var shortcuts: [String] = []
    public var widgets: [WidgetKind] = [.media, .calendar, .timer, .notes, .tasks, .shortcuts, .mirror]
    public init() {}
}

public enum StoreError: LocalizedError {
    case corrupted(String), invalidPath, missingFile
    public var errorDescription: String? {
        switch self {
        case .corrupted(let file): return "Could not read \(file). Your existing data has been preserved."
        case .invalidPath: return "This file is outside the managed tray."
        case .missingFile: return "This file is no longer available."
        }
    }
}

/// Atomic writes + last valid backup. Never overwrite damaged user data with empty defaults.
public final class JSONDiskStore<Value: Codable> {
    public let url: URL
    public var backupURL: URL { url.appendingPathExtension("backup") }
    public init(url: URL) { self.url = url }
    public func load(default fallback: @autoclosure () -> Value) throws -> Value {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) && !fm.fileExists(atPath: backupURL.path) { return fallback() }
        for candidate in [url, backupURL] {
            if let data = try? Data(contentsOf: candidate), let value = try? JSONDecoder().decode(Value.self, from: data) {
                return value
            }
        }
        throw StoreError.corrupted(url.lastPathComponent)
    }
    public func save(_ value: Value) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(value)
        if let previous = try? Data(contentsOf: url), (try? JSONDecoder().decode(Value.self, from: previous)) != nil {
            try previous.write(to: backupURL, options: .atomic)
        }
        try data.write(to: url, options: .atomic)
    }
}

public struct ShelfItem: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var relativePath: String
    public var added: Date
    public init(id: UUID, name: String, relativePath: String) {
        self.id = id; self.name = name; self.relativePath = relativePath; self.added = Date()
    }
}

/// Access exclusively on the shelf worker queue. Originals survive all default operations.
public final class ShelfRepository: @unchecked Sendable {
    public let root: URL
    private let lock = NSRecursiveLock()
    private var storedItems: [ShelfItem]
    public var items: [ShelfItem] { lock.lock(); defer { lock.unlock() }; return storedItems }
    private let disk: JSONDiskStore<[ShelfItem]>
    public init(root: URL) throws {
        self.root = root
        disk = JSONDiskStore(url: root.appendingPathComponent("index.json"))
        storedItems = try disk.load(default: [])
    }
    public func fileURL(for item: ShelfItem) throws -> URL {
        let base = root.appendingPathComponent("Files", isDirectory: true).standardizedFileURL
        let candidate = base.appendingPathComponent(item.relativePath).standardizedFileURL
        guard candidate.path.hasPrefix(base.path + "/"),
              candidate.resolvingSymlinksInPath().path.hasPrefix(base.resolvingSymlinksInPath().path + "/") else {
            throw StoreError.invalidPath
        }
        return candidate
    }
    @discardableResult public func add(_ source: URL, move: Bool = false) throws -> ShelfItem {
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        guard source.isFileURL, fm.fileExists(atPath: source.path) else { throw StoreError.missingFile }
        guard try source.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw StoreError.invalidPath }
        let id = UUID()
        let item = ShelfItem(id: id, name: source.lastPathComponent,
                             relativePath: id.uuidString + "/" + source.lastPathComponent)
        let target = try fileURL(for: item)
        // Dropping the tray back onto itself must not recursively copy its storage.
        let canonical = source.resolvingSymlinksInPath().path
        let storage = root.resolvingSymlinksInPath().path
        guard !canonical.hasPrefix(storage + "/"), !storage.hasPrefix(canonical + "/"), canonical != storage else {
            throw StoreError.invalidPath
        }
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if move { try fm.moveItem(at: source, to: target) } else { try fm.copyItem(at: source, to: target) }
        do {
            try disk.save(items + [item]); storedItems.append(item)
        } catch {
            if move { try? fm.moveItem(at: target, to: source) } else { try? fm.removeItem(at: target) }
            throw error
        }
        return item
    }
    public func remove(_ item: ShelfItem, recycle: (URL) throws -> Void) throws {
        lock.lock(); defer { lock.unlock() }
        let file = try fileURL(for: item)
        if FileManager.default.fileExists(atPath: file.path) { try recycle(file) }
        let updated = items.filter { $0.id != item.id }
        try disk.save(updated); storedItems = updated
    }
}

public struct MediaSnapshot: Equatable, Sendable {
    public var title = ""
    public var artist = ""
    public var album = ""
    public var bundleID = ""
    public var trackID = ""
    public var playing = false
    public var duration: Double = 0
    public var elapsed: Double = 0
    public var timestamp = Date()
    public var artwork: Data?
    public init() {}
    public var available: Bool { !title.isEmpty }
    public var identity: MediaIdentity {
        MediaIdentity(bundleID: bundleID, trackID: trackID,
                      title: title, artist: artist, album: album)
    }
    /// System and direct player IDs use different namespaces. Require matching
    /// source and metadata before accepting artwork from the system adapter.
    public func matchesSystemTrack(_ other: MediaSnapshot) -> Bool {
        available && other.available && !bundleID.isEmpty && bundleID == other.bundleID
            && title == other.title && artist == other.artist && album == other.album
            && duration > 0 && other.duration > 0 && abs(duration - other.duration) < 2
    }
    public func position(at now: Date) -> Double {
        let time = max(0, elapsed + (playing ? now.timeIntervalSince(timestamp) : 0))
        return duration > 0 ? min(duration, time) : time
    }
    public static func decode(_ data: Data, now: Date = Date()) throws -> MediaSnapshot {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let payload = json["payload"] as? [String: Any] ?? json
        var result = MediaSnapshot()
        result.title = payload["title"] as? String ?? ""
        result.artist = payload["artist"] as? String ?? ""
        result.album = payload["album"] as? String ?? ""
        result.bundleID = payload["bundleIdentifier"] as? String ?? ""
        result.trackID = [payload["contentItemIdentifier"], payload["uniqueIdentifier"]]
            .compactMap { ($0 as? String) ?? ($0 as? NSNumber)?.stringValue }
            .first(where: { !$0.isEmpty }) ?? ""
        result.playing = payload["playing"] as? Bool ?? false
        result.duration = (payload["durationMicros"] as? Double ?? 0) / 1_000_000
        result.elapsed = (payload["elapsedTimeMicros"] as? Double ?? 0) / 1_000_000
        result.timestamp = (payload["timestampEpochMicros"] as? Double).map { Date(timeIntervalSince1970: $0 / 1_000_000) } ?? now
        if let base64 = payload["artworkData"] as? String { result.artwork = Data(base64Encoded: base64) }
        return result
    }
}
