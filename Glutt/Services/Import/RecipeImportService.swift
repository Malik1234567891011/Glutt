import Foundation
import UIKit
import Vision

enum ImportError: LocalizedError {
    case invalidURL
    case fetchFailed
    case unreadableImage
    case nothingFound

    var errorDescription: String? {
        switch self {
        case .invalidURL: "That doesn't look like a valid link."
        case .fetchFailed: "Couldn't load that page. Check the link and your connection."
        case .unreadableImage: "Couldn't read any text from that image."
        case .nothingFound: "Couldn't find a recipe there."
        }
    }
}

/// Orchestrates all import paths: web links, social links, and screenshots.
enum RecipeImportService {

    /// Browser-like user agent — many recipe sites block default URLSession agents.
    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    // MARK: - Link import

    static func importFrom(urlString: String) async throws -> ImportedRecipeDraft {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed) else { throw ImportError.invalidURL }
        if components.scheme == nil { components.scheme = "https" }
        guard let url = components.url, url.host != nil else { throw ImportError.invalidURL }
        return try await importFrom(url: url)
    }

    static func importFrom(url: URL) async throws -> ImportedRecipeDraft {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ImportError.fetchFailed
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else {
            throw ImportError.fetchFailed
        }

        let finalURL = http.url ?? url
        return RecipeHTMLParser.parse(html: html, sourceURL: finalURL)
    }

    // MARK: - Screenshot / photo import (on-device OCR)

    static func importFrom(imageData: Data) async throws -> ImportedRecipeDraft {
        guard let uiImage = UIImage(data: imageData), let cgImage = uiImage.cgImage else {
            throw ImportError.unreadableImage
        }

        let text = try await recognizeText(in: cgImage)
        guard !text.isEmpty else { throw ImportError.unreadableImage }

        var draft = TextRecipeParser.parse(text: text)
        draft.platform = .screenshot
        draft.issues.append("Imported from a screenshot — double-check quantities")
        return draft
    }

    private static func recognizeText(in image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            do {
                try VNImageRequestHandler(cgImage: image).perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

/// Hook for the Phase 6 AI layer: re-extract or clean up a draft with an LLM.
/// Everything compiles and works without it — AI is never load-bearing.
protocol DraftCleanupService {
    func cleanUp(draft: ImportedRecipeDraft) async throws -> ImportedRecipeDraft
}
