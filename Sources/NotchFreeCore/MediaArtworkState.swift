import Foundation

public struct MediaIdentity: Hashable, Sendable {
    public let bundleID: String
    public let trackID: String
    // Retain metadata as well: some players recycle IDs or initially omit them.
    public let title: String
    public let artist: String
    public let album: String
}

public struct ArtworkRequest: Equatable, Sendable {
    public let identity: MediaIdentity
    fileprivate let revision: UInt64
}

/// The same state gate is used by live artwork loading and deterministic checks.
public struct MediaArtworkState: Sendable {
    public private(set) var snapshot = MediaSnapshot()
    private var revision: UInt64 = 0
    public init() {}

    public var request: ArtworkRequest? {
        snapshot.available ? ArtworkRequest(identity: snapshot.identity, revision: revision) : nil
    }

    public mutating func update(_ incoming: MediaSnapshot) {
        let sameTrack = incoming.available && snapshot.available && incoming.identity == snapshot.identity
        if !sameTrack { revision &+= 1 }
        var next = incoming.available ? incoming : MediaSnapshot()
        if sameTrack && next.artwork == nil { next.artwork = snapshot.artwork }
        snapshot = next
    }

    public mutating func reset() {
        revision &+= 1
        snapshot = MediaSnapshot()
    }

    public func accepts(_ request: ArtworkRequest) -> Bool {
        self.request == request
    }

    @discardableResult public mutating func apply(_ data: Data, for request: ArtworkRequest) -> Bool {
        guard accepts(request), !data.isEmpty else { return false }
        snapshot.artwork = data
        return true
    }
}
