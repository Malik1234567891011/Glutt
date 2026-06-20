import Foundation

/// A YouTube cooking clip surfaced in Discover. Transient — never persisted.
struct DiscoverVideo: Decodable, Identifiable, Equatable {
    let videoId: String
    let title: String
    let creator: String?
    let thumbnailURL: String?
    let durationSeconds: Int?

    var id: String { videoId }

    var watchURL: URL {
        URL(string: "https://www.youtube.com/watch?v=\(videoId)")!
    }
}

/// One page of Discover results from the proxy.
struct DiscoverResponse: Decodable, Equatable {
    let videos: [DiscoverVideo]
    let nextPageToken: String?
}
