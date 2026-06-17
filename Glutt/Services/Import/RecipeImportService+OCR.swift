import Foundation
import UIKit
import Vision

extension RecipeImportService {

    /// Screenshot / photo import (on-device OCR). App-only — the share
    /// extension never uses this path, so it stays out of the shared service.
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
