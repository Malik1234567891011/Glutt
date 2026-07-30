import Foundation

/// One approved demonstration window for a CookPlan step (YouTube embed, not a hosted MP4).
struct StepClip: Codable, Equatable, Identifiable, Sendable {
    var id: String { "\(stepID)-\(youtubeVideoID)-\(startSeconds)" }

    let stepID: String
    let youtubeVideoID: String
    let startSeconds: Int
    let endSeconds: Int
    let durationSeconds: Int
    let matchType: String
    let confidence: Double
    let watchLabel: String
    let notice: String
    let primaryAction: String
    let visualCue: String

    enum CodingKeys: String, CodingKey {
        case stepID = "step_id"
        case youtubeVideoID = "youtube_video_id"
        case startSeconds = "start_seconds"
        case endSeconds = "end_seconds"
        case durationSeconds = "duration_seconds"
        case matchType = "match_type"
        case confidence
        case watchLabel = "watch_label"
        case notice
        case primaryAction = "primary_action"
        case visualCue = "visual_cue"
    }
}

struct StepClipIndexResponse: Codable, Equatable, Sendable {
    let youtubeVideoID: String
    let clips: [StepClip]
    let cached: Bool?
    let model: String?

    enum CodingKeys: String, CodingKey {
        case youtubeVideoID = "youtube_video_id"
        case clips, cached, model
    }
}
