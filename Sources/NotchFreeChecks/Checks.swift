import Foundation
import NotchFreeCore

@main enum Checks {
    static var count = 0
    static func expect(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
        guard try condition() else { throw NSError(domain: "Check", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }
        count += 1; print("✓ \(name)")
    }
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        var state = Presentation()
        state.open(.tray); state.editing = true
        state.show(Activity(title: "Volume", symbol: "speaker", duration: 2, now: now))
        try expect(state.visibleActivity == nil, "HUD does not replace an open editor")
        state.close(); try expect(state.expanded, "Pointer exit preserves editing")
        state.editing = false; state.dragging = true; state.close()
        try expect(state.expanded, "Pointer exit preserves dragging")
        state.close(force: true); try expect(!state.expanded && !state.dragging && !state.editing, "Escape clears interaction locks")
        try expect(state.visibleActivity != nil, "A live activity returns after close")
        state.tick(now: now.addingTimeInterval(3)); try expect(state.visibleActivity == nil, "Expired activities cannot return later")
        for _ in 0..<100 { state.open(); state.close(force: true) }
        try expect(!state.expanded, "100 reducer cycles return to idle")

        var timer = Countdown()
        timer.start(seconds: 60, now: now); timer.pause(now: now.addingTimeInterval(10))
        try expect(timer.remaining(at: now.addingTimeInterval(100)) == 50, "Paused timer survives elapsed wall time")
        timer.resume(now: now.addingTimeInterval(100))
        try expect(timer.remaining(at: now.addingTimeInterval(120)) == 30, "Resume keeps remaining duration")
        let encoded = try JSONEncoder().encode(timer)
        timer = try JSONDecoder().decode(Countdown.self, from: encoded)
        try expect(timer.expire(now: now.addingTimeInterval(500)), "Persisted timer expires after sleep/relaunch")
        try expect(!timer.expire(now: now.addingTimeInterval(501)), "Timer completion fires only once")
        try expect(timer.remaining(at: now) == 0, "Completed timer stays at zero")
        timer.reset(); try expect(timer.remaining(at: now) == 60, "Reset restores selected duration")

        let media = try MediaSnapshot.decode(Data("""
        {"payload":{"title":"Track","artist":"Artist","playing":true,"durationMicros":120000000,"elapsedTimeMicros":10000000,"timestampEpochMicros":1000000000}}
        """.utf8), now: now)
        try expect(media.position(at: now.addingTimeInterval(5)) == 15, "Now Playing uses epoch microseconds correctly")
        try expect(media.position(at: now.addingTimeInterval(500)) == 120, "Progress clamps to duration")
        let empty = try MediaSnapshot.decode(Data("{\"payload\":{}}".utf8))
        try expect(!empty.available, "Cleared metadata removes stale artwork and title")
        try artworkChecks()
        try panelChecks()
        try timerInputChecks()
        try englishChecks()

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NotchFreeChecks-" + UUID().uuidString)
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let disk = JSONDiskStore<UserLibrary>(url: root.appendingPathComponent("library.json"))
        var library = UserLibrary(); library.note = "Do not lose me"; library.todos = [Todo(text: "Ship")]; library.timer = timer
        try disk.save(library)
        library.note = "Version two"; try disk.save(library)
        try expect(tryRead(disk).note == "Version two", "Library survives a fresh load")
        try Data("broken".utf8).write(to: disk.url)
        try expect(tryRead(disk).note == "Do not lose me", "Corrupt primary recovers last valid backup")
        try Data("broken too".utf8).write(to: disk.backupURL)
        do { _ = try disk.load(default: UserLibrary()); try expect(false, "Corrupt files must throw") }
        catch let error as StoreError { try expect(error.localizedDescription.contains("preserved"), "Double corruption does not silently erase data") }
        try expect(String(data: try Data(contentsOf: disk.url), encoding: .utf8) == "broken", "Load never overwrites damaged data")

        let source = root.appendingPathComponent("Original.txt")
        try Data("precious".utf8).write(to: source)
        let trayRoot = root.appendingPathComponent("Tray")
        let tray = try ShelfRepository(root: trayRoot)
        let first = try tray.add(source), second = try tray.add(source)
        try expect(first.relativePath != second.relativePath, "Duplicate names have independent storage")
        try expect(fm.fileExists(atPath: source.path), "Import preserves the original")
        let firstURL = try tray.fileURL(for: first)
        try expect(try Data(contentsOf: firstURL) == Data("precious".utf8), "Tray copy preserves bytes")
        let reload = try ShelfRepository(root: trayRoot)
        try expect(reload.items.count == 2, "Tray survives restart")
        do { try tray.remove(first) { _ in throw StoreError.missingFile }; try expect(false, "Failed removal must throw") }
        catch { try expect(tray.items.count == 2, "Failed recycling retains metadata") }
        try tray.remove(first) { try fm.moveItem(at: $0, to: root.appendingPathComponent("Recycled.txt")) }
        try expect(fm.fileExists(atPath: source.path), "Removing a tray copy preserves its source")
        try expect(tray.items.count == 1, "Successful removal updates manifest")
        let malicious = ShelfItem(id: UUID(), name: "escape", relativePath: "../../Original.txt")
        do { _ = try tray.fileURL(for: malicious); try expect(false, "Traversal must fail") }
        catch { try expect(true, "Manifest traversal cannot escape managed storage") }
        do { _ = try tray.add(trayRoot); try expect(false, "Recursive import must fail") }
        catch { try expect(true, "Dropping tray storage into itself is rejected") }
        let moveSource = root.appendingPathComponent("Move.txt"); try Data("move".utf8).write(to: moveSource)
        let moved = try tray.add(moveSource, move: true)
        try expect(!fm.fileExists(atPath: moveSource.path), "Explicit move removes source only after moving")
        try expect(fm.fileExists(atPath: try tray.fileURL(for: moved).path), "Explicit move keeps destination available")
        print("\n\(count) checks passed.")
    }
    static func artworkChecks() throws {
        var first = MediaSnapshot()
        first.bundleID = "com.apple.Music"; first.trackID = "music-1"
        first.title = "Same title"; first.artist = "Artist one"; first.album = "Album one"; first.duration = 120
        let cover = Data([1, 2, 3])
        var state = MediaArtworkState()
        state.update(first)
        let original = state.request!
        try expect(state.apply(cover, for: original), "Current track accepts its delayed artwork")
        var paused = first; paused.playing = false; paused.elapsed = 40
        state.update(paused)
        try expect(state.snapshot.artwork == cover, "Pause and seek preserve the current cover")
        try expect(state.request == original, "Playback position does not start a new artwork session")

        var other = first; other.trackID = "music-2"
        state.update(other)
        try expect(state.snapshot.artwork == nil, "A different ID with identical metadata clears the old cover")
        try expect(!state.apply(cover, for: original), "A late cover cannot overwrite the next track")
        state.update(first)
        try expect(!state.apply(cover, for: original), "A to B to A switching still rejects the first A request")
        let beforeReconnect = state.request!
        state.reset(); state.update(first)
        try expect(!state.apply(cover, for: beforeReconnect), "Reconnect invalidates in-flight artwork for the same track")
        let beforeStop = state.request!
        state.update(MediaSnapshot())
        try expect(state.request == nil && !state.snapshot.available && state.snapshot.artwork == nil, "Stopping clears both media and artwork state")
        try expect(!state.apply(cover, for: beforeStop), "Stopped media cannot receive delayed artwork")

        first.trackID = ""; other = first; other.artist = "Artist two"
        try expect(first.identity != other.identity, "Missing IDs still distinguish artists with identical song titles")
        other = first; other.album = "Different album"
        try expect(first.identity != other.identity, "Missing IDs distinguish album versions")
        other = first; other.bundleID = "com.spotify.client"
        try expect(first.identity != other.identity, "Artwork cache identities separate Music and Spotify")
        try expect(!first.matchesSystemTrack(other), "System fallback rejects another media app")
        other = first; other.artist = "Different artist"
        try expect(!first.matchesSystemTrack(other), "System fallback rejects an unrelated track with the same title")
        other = first; other.duration = 150
        try expect(!first.matchesSystemTrack(other), "System fallback rejects a different recording duration")
        other = first; other.trackID = "system-specific-id"; other.duration += 0.2
        try expect(first.matchesSystemTrack(other), "Matching Music metadata allows system artwork across ID namespaces")

        let decoded = try MediaSnapshot.decode(Data("""
        {"payload":{"title":"Track","contentItemIdentifier":"content-id","uniqueIdentifier":123,"artworkData":"AQID"}}
        """.utf8))
        try expect(decoded.trackID == "content-id" && decoded.artwork == cover, "System payload decodes track identity and artwork bytes")
        let numeric = try MediaSnapshot.decode(Data("{\"title\":\"Track\",\"uniqueIdentifier\":123}".utf8))
        try expect(numeric.trackID == "123", "Numeric system track IDs remain stable strings")
        let missing = try MediaSnapshot.decode(Data("{\"title\":\"Track\",\"artworkData\":\"invalid!\"}".utf8))
        try expect(missing.artwork == nil, "Malformed artwork keeps metadata usable")
    }

    static func panelChecks() throws {
        func size(expanded: Bool = true, activity: Bool = false, compact: Bool = true,
                  message: Bool = false, trayError: Bool = false, width: Double = 720) -> PanelSize {
            PanelMetrics.visibleSize(notchWidth: 180, notchHeight: 32, panelWidth: 720,
                                     availableWidth: width, expanded: expanded, activity: activity,
                                     compact: compact, message: message, trayError: trayError)
        }
        let opened = size()
        try expect(opened.width == 720 && opened.height == 244, "Expanded panel retains width and removes another 32 points of height")
        try expect(size(expanded: false, compact: false).height == 35, "Idle notch height is preserved")
        try expect(size(expanded: false).width == 284, "Compact playback strip width is preserved")
        try expect(size(expanded: false, activity: true).height == 80, "Activity previews keep their existing height")
        try expect(size(width: 580).width == 580, "Shared drawing and pointer geometry clamps to a narrow display")
        try expect(size(message: true).height == opened.height + 40, "A panel message adds room above the full widget")
        try expect(size(trayError: true).height == opened.height + 34, "Tray errors get room without shrinking file tiles")
        try expect(size(message: true, trayError: true).height + PanelMetrics.shadowGutter == PanelMetrics.envelopeHeight(notchHeight: 32), "Both messages and shadow fit the AppKit hosting envelope")
    }
    static func tryRead(_ disk: JSONDiskStore<UserLibrary>) -> UserLibrary { (try? disk.load(default: UserLibrary())) ?? UserLibrary() }
}
