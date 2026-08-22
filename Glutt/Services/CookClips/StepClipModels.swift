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

    init(
        stepID: String, youtubeVideoID: String, startSeconds: Int, endSeconds: Int,
        durationSeconds: Int, matchType: String, confidence: Double,
        watchLabel: String, notice: String, primaryAction: String, visualCue: String
    ) {
        self.stepID = stepID
        self.youtubeVideoID = youtubeVideoID
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.durationSeconds = durationSeconds
        self.matchType = matchType
        self.confidence = confidence
        self.watchLabel = watchLabel
        self.notice = notice
        self.primaryAction = primaryAction
        self.visualCue = visualCue
    }

    /// Tolerant of the fields the two proxy phases disagree about.
    ///
    /// `ground` returns every key below. `refine` returns a narrower clip:
    /// no `youtube_video_id`, no `primary_action`, no `visual_cue`. The
    /// synthesized decoder needed all three, so refine threw `keyNotFound`,
    /// `clips()` threw with it, and **every** uncached clip fetch in the app
    /// failed after paying for both Gemini calls. The symptom was silent: one
    /// line in the debug log reading "index failed — The data couldn't be read
    /// because it is missing", and a cook with no clips.
    ///
    /// Same treatment as `CookPlan.PlanStep`: required fields stay required so a
    /// genuinely broken payload still fails, and everything the server may
    /// legitimately omit degrades to empty.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stepID = try container.decode(String.self, forKey: .stepID)
        startSeconds = try container.decode(Int.self, forKey: .startSeconds)
        endSeconds = try container.decode(Int.self, forKey: .endSeconds)
        durationSeconds = try container.decode(Int.self, forKey: .durationSeconds)
        matchType = try container.decode(String.self, forKey: .matchType)
        confidence = try container.decode(Double.self, forKey: .confidence)
        watchLabel = try container.decode(String.self, forKey: .watchLabel)
        notice = try container.decode(String.self, forKey: .notice)
        // Backfilled from the response root by `StepClipIndexResponse` when the
        // clip itself does not carry it.
        youtubeVideoID = (try? container.decode(String.self, forKey: .youtubeVideoID)) ?? ""
        primaryAction = (try? container.decode(String.self, forKey: .primaryAction)) ?? ""
        visualCue = (try? container.decode(String.self, forKey: .visualCue)) ?? ""
    }

    /// The same clip, told which video it came from.
    func withVideoID(_ id: String) -> StepClip {
        guard youtubeVideoID.isEmpty else { return self }
        return StepClip(
            stepID: stepID, youtubeVideoID: id,
            startSeconds: startSeconds, endSeconds: endSeconds,
            durationSeconds: durationSeconds, matchType: matchType,
            confidence: confidence, watchLabel: watchLabel, notice: notice,
            primaryAction: primaryAction, visualCue: visualCue)
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

    /// Stamps the root video id onto any clip that arrived without one, so
    /// `StepClip.id` and the player always have it regardless of which phase
    /// produced the clip.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let video = try container.decode(String.self, forKey: .youtubeVideoID)
        youtubeVideoID = video
        cached = try? container.decode(Bool.self, forKey: .cached)
        model = try? container.decode(String.self, forKey: .model)
        clips = ((try? container.decode([StepClip].self, forKey: .clips)) ?? [])
            .map { $0.withVideoID(video) }
    }

    init(youtubeVideoID: String, clips: [StepClip], cached: Bool? = nil, model: String? = nil) {
        self.youtubeVideoID = youtubeVideoID
        self.clips = clips
        self.cached = cached
        self.model = model
    }
}
