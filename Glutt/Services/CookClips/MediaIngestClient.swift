import Foundation

/// Control-plane client for background technique-clip ingest.
/// Enqueue is cheap; analyze (Gemini) runs after save and must not block import UI.
actor MediaIngestClient {
    static let shared = MediaIngestClient()

    var baseURL: String = Secrets.aiProxyBaseURL
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    var clientKey: String = Secrets.aiProxyClientKey
        .trimmingCharacters(in: .whitespacesAndNewlines)

    struct EnqueueResult: Sendable {
        var externalID: String
        var sourceAssetID: String?
        var jobID: String?
        var mediaStatus: String
        var progress: Double
        var detail: String
        var reused: Bool
    }

    struct StatusResult: Sendable {
        var found: Bool
        var externalID: String
        var mediaStatus: String
        var progress: Double
        var detail: String
        var sourceAssetID: String?
        var jobID: String?
        var approvedSegments: Int
        var readyClips: Int
    }

    func enqueue(sourceURL: String, title: String? = nil, creator: String? = nil) async throws -> EnqueueResult {
        var body: [String: Any] = [
            "action": "enqueue",
            "source_url": sourceURL,
        ]
        if let title, !title.isEmpty { body["title"] = title }
        if let creator, !creator.isEmpty { body["creator_name"] = creator }
        let json = try await postJSON(body)
        let external = (json["external_id"] as? String)
            ?? MediaSourceID.from(sourceURL: sourceURL)
            ?? ""
        let asset = json["source_asset"] as? [String: Any]
        let job = json["job"] as? [String: Any]
        return EnqueueResult(
            externalID: external,
            sourceAssetID: asset?["id"] as? String,
            jobID: job?["id"] as? String,
            mediaStatus: (asset?["status"] as? String) ?? "queued",
            progress: 0.1,
            detail: (json["reused"] as? Bool) == true ? "Clips already queued" : "Queued for clipping",
            reused: (json["reused"] as? Bool) ?? false
        )
    }

    func analyze(
        sourceURL: String,
        externalID: String,
        recipeTitle: String,
        steps: [(id: String, title: String, instruction: String)]
    ) async throws -> StatusResult {
        let stepPayload: [[String: Any]] = steps.map {
            ["id": $0.id, "title": $0.title, "instruction": $0.instruction]
        }
        let body: [String: Any] = [
            "action": "analyze",
            "source_url": sourceURL,
            "external_id": externalID,
            "recipe_title": recipeTitle,
            "steps": stepPayload,
        ]
        let json = try await postJSON(body)
        if (json["skipped"] as? Bool) == true {
            return StatusResult(
                found: true,
                externalID: externalID,
                mediaStatus: "queued",
                progress: 0.2,
                detail: (json["reason"] as? String) ?? "Waiting for media worker",
                sourceAssetID: json["source_asset_id"] as? String,
                jobID: nil,
                approvedSegments: 0,
                readyClips: 0
            )
        }
        return StatusResult(
            found: true,
            externalID: externalID,
            mediaStatus: (json["media_status"] as? String) ?? "indexed",
            progress: (json["progress"] as? Double) ?? 0.55,
            detail: (json["detail"] as? String) ?? "Moments indexed",
            sourceAssetID: json["source_asset_id"] as? String,
            jobID: nil,
            approvedSegments: (json["segments_written"] as? Int) ?? 0,
            readyClips: 0
        )
    }

    func status(externalID: String) async throws -> StatusResult {
        guard var comps = URLComponents(string: "\(baseURL)/media/ingest") else {
            throw URLError(.badURL)
        }
        comps.queryItems = [
            URLQueryItem(name: "action", value: "status"),
            URLQueryItem(name: "external_id", value: externalID),
        ]
        guard let url = comps.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue(clientKey, forHTTPHeaderField: "x-glutt-proxy-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "MediaIngestClient", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [
                NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "status failed",
            ])
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let asset = json["source_asset"] as? [String: Any]
        let job = json["job"] as? [String: Any]
        return StatusResult(
            found: (json["found"] as? Bool) ?? false,
            externalID: (json["external_id"] as? String) ?? externalID,
            mediaStatus: (json["media_status"] as? String) ?? "queued",
            progress: (json["progress"] as? Double) ?? 0,
            detail: (json["detail"] as? String) ?? "",
            sourceAssetID: asset?["id"] as? String,
            jobID: job?["id"] as? String,
            approvedSegments: (json["approved_segments"] as? Int) ?? 0,
            readyClips: (json["ready_clips"] as? Int) ?? 0
        )
    }

    private func postJSON(_ body: [String: Any]) async throws -> [String: Any] {
        guard !baseURL.isEmpty, !clientKey.isEmpty else {
            throw NSError(domain: "MediaIngestClient", code: 503, userInfo: [
                NSLocalizedDescriptionKey: "AI proxy not configured",
            ])
        }
        guard let url = URL(string: "\(baseURL)/media/ingest") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue(clientKey, forHTTPHeaderField: "x-glutt-proxy-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "MediaIngestClient", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [
                NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "ingest failed",
            ])
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
