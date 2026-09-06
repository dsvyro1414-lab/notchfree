import AppKit
import ImageIO
import UniformTypeIdentifiers
import NotchFreeCore

struct DirectMediaMetadata: Sendable {
    var snapshot: MediaSnapshot
    var artworkURL: String
}

enum PlayerAutomation {
    private static let queue = DispatchQueue(label: "NotchFree.player-automation", qos: .utility)

    /// Decode descriptors on the worker queue, including Music's binary artwork.
    /// Track strings are data in an Apple event list, never script source or delimiters.
    static func execute<T: Sendable>(_ script: String,
                                     decode: @escaping @Sendable (NSAppleEventDescriptor) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    var error: NSDictionary?
                    let source = "with timeout of 5 seconds\n\(script)\nend timeout"
                    let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                    if let error {
                        throw NSError(domain: "Automation", code: error[NSAppleScript.errorNumber] as? Int ?? 1,
                                      userInfo: [NSLocalizedDescriptionKey: error[NSAppleScript.errorMessage] as? String ?? "Automation failed"])
                    }
                    guard let result else { throw CocoaError(.coderReadCorrupt) }
                    continuation.resume(returning: try decode(result))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    static func string(_ script: String) async throws -> String {
        try await execute(script) { $0.stringValue ?? "" }
    }

    static func metadata(spotify: Bool) async throws -> DirectMediaMetadata {
        let id = spotify ? "com.spotify.client" : "com.apple.Music"
        let identifier = spotify ? "id" : "persistent ID"
        let urlQuery = spotify ? "try\nset coverURL to artwork url of currentItem as text\nend try" : ""
        return try await execute("""
        tell application id "\(id)"
            if player state is stopped then return {}
            set currentItem to current track
            set itemID to ""
            try
                set itemID to \(identifier) of currentItem as text
            end try
            set coverURL to ""
            \(urlQuery)
            return {itemID, name of currentItem as text, artist of currentItem as text, album of currentItem as text, duration of currentItem, player position, player state as text, coverURL}
        end tell
        """) { result in
            guard result.numberOfItems == 8 else { return DirectMediaMetadata(snapshot: MediaSnapshot(), artworkURL: "") }
            var snapshot = decodeTrack(result, bundleID: id, durationScale: spotify ? 1000 : 1)
            snapshot.elapsed = result.atIndex(6)?.doubleValue ?? 0
            snapshot.playing = result.atIndex(7)?.stringValue == "playing"
            return DirectMediaMetadata(snapshot: snapshot, artworkURL: result.atIndex(8)?.stringValue ?? "")
        }
    }

    static func musicArtwork(for expected: MediaSnapshot) async throws -> Data? {
        try await execute("""
        tell application id "com.apple.Music"
            if player state is stopped then return {}
            set currentItem to current track
            set itemID to ""
            try
                set itemID to persistent ID of currentItem as text
            end try
            if (count of artworks of currentItem) is 0 then return {}
            return {itemID, name of currentItem as text, artist of currentItem as text, album of currentItem as text, duration of currentItem, raw data of artwork 1 of currentItem}
        end tell
        """) { result in
            guard result.numberOfItems == 6 else { return nil }
            let actual = decodeTrack(result, bundleID: "com.apple.Music", durationScale: 1)
            guard actual.identity == expected.identity else { return nil }
            return result.atIndex(6)?.data
        }
    }

    private static func decodeTrack(_ result: NSAppleEventDescriptor, bundleID: String, durationScale: Double) -> MediaSnapshot {
        var snapshot = MediaSnapshot()
        snapshot.bundleID = bundleID
        snapshot.trackID = result.atIndex(1)?.stringValue ?? ""
        snapshot.title = result.atIndex(2)?.stringValue ?? ""
        snapshot.artist = result.atIndex(3)?.stringValue ?? ""
        snapshot.album = result.atIndex(4)?.stringValue ?? ""
        snapshot.duration = (result.atIndex(5)?.doubleValue ?? 0) / durationScale
        snapshot.timestamp = Date()
        return snapshot
    }
}

enum MediaArtworkLoader {
    private static let maximumBytes = 8 * 1024 * 1024
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        return URLSession(configuration: configuration)
    }()

    static func load(for snapshot: MediaSnapshot, spotifyURL: String, scriptURL: URL?, frameworkURL: URL?) async -> Data? {
        guard !Task.isCancelled else { return nil }
        if snapshot.bundleID == "com.spotify.client" {
            guard let url = URL(string: spotifyURL), url.scheme == "https" else { return nil }
            do {
                let (bytes, response) = try await session.bytes(from: url)
                guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                      response.url?.scheme == "https", response.expectedContentLength <= maximumBytes else { return nil }
                var data = Data()
                for try await byte in bytes {
                    guard !Task.isCancelled, data.count < maximumBytes else { return nil }
                    data.append(byte)
                }
                return normalized(data)
            } catch { return nil }
        }
        guard snapshot.bundleID == "com.apple.Music" else { return nil }
        if let data = try? await PlayerAutomation.musicArtwork(for: snapshot),
           !Task.isCancelled, let image = normalized(data) { return image }
        guard !Task.isCancelled, let scriptURL, let frameworkURL else { return nil }
        // Some streamed Music tracks expose their artwork only through Now Playing.
        // Never borrow the cover of a different foreground player or track.
        guard let output = try? await CommandRunner.run("/usr/bin/perl", [scriptURL.path, frameworkURL.path, "get", "--micros"], timeout: 6),
              !Task.isCancelled, let system = try? MediaSnapshot.decode(Data(output.utf8)),
              snapshot.matchesSystemTrack(system), let data = system.artwork else { return nil }
        return normalized(data)
    }

    private static func normalized(_ data: Data) -> Data? {
        guard !data.isEmpty, data.count <= maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 512,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

@MainActor final class MediaArtworkCache {
    private var images: [MediaIdentity: Data] = [:]
    private var recent: [MediaIdentity] = []
    func image(for identity: MediaIdentity) -> Data? {
        guard let data = images[identity] else { return nil }
        recent.removeAll { $0 == identity }; recent.append(identity)
        return data
    }
    func insert(_ data: Data, for identity: MediaIdentity) {
        images[identity] = data
        recent.removeAll { $0 == identity }; recent.append(identity)
        while recent.count > 20 || images.values.reduce(0, { $0 + $1.count }) > 8 * 1024 * 1024 {
            images.removeValue(forKey: recent.removeFirst())
        }
    }
}
