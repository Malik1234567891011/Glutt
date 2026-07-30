import Foundation

/// Native Glutt clip (downloaded master → materialized MP4 / 9:16 derivative).
struct NativeStepClip: Codable, Equatable, Identifiable, Sendable {
    var id: String { segmentID }

    let segmentID: String
    let startSeconds: Double
    let endSeconds: Double
    let durationSeconds: Double
    let watchLabel: String
    let teachingLabel: String?
    let notice: String
    let visualCue: String
    let stepKeywords: [String]
    let presentationMode: String?
    let playbackURL: URL
    let thumbnailURL: URL?
    let masterURL: URL?
    let usesVirtualRange: Bool
    let creatorAttribution: String?

    /// User-facing clip headline (no timestamps).
    var displayLabel: String {
        let t = (teachingLabel ?? watchLabel).trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Watch example" : t
    }

    var durationLabel: String {
        let secs = max(1, Int(durationSeconds.rounded()))
        return "\(secs) sec"
    }

    enum CodingKeys: String, CodingKey {
        case segmentID = "segment_id"
        case startSeconds = "start_seconds"
        case endSeconds = "end_seconds"
        case durationSeconds = "duration_seconds"
        case watchLabel = "watch_label"
        case teachingLabel = "teaching_label"
        case notice
        case visualCue = "visual_cue"
        case stepKeywords = "step_keywords"
        case presentationMode = "presentation_mode"
        case playbackURL = "playback_url"
        case thumbnailURL = "thumbnail_url"
        case masterURL = "master_url"
        case usesVirtualRange = "uses_virtual_range"
        case creatorAttribution = "creator_attribution"
    }
}

struct NativePilotClipsResponse: Codable, Equatable, Sendable {
    let sourceAssetID: String
    let status: String
    let durationSeconds: Double?
    let title: String?
    let clips: [NativeStepClip]

    enum CodingKeys: String, CodingKey {
        case sourceAssetID = "source_asset_id"
        case status
        case durationSeconds = "duration_seconds"
        case title
        case clips
    }
}

enum PollyMediaState: Equatable, Sendable {
    case idle
    case preparing(segmentID: String)
    case playing(segmentID: String, muted: Bool)
    case paused(segmentID: String)
    case finished(segmentID: String)

    var isPlaying: Bool {
        if case .playing = self { return true }
        return false
    }
}
