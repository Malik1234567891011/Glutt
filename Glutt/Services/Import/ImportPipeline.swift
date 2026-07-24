import Foundation

/// One orchestration of the link-import flow, shared by the in-app importer and
/// the share extension: fetch the page, optionally listen to the video, then
/// run the AI passes that improve the draft.
/// `progress` reports the user-facing status line for each phase.
enum ImportPipeline {

    /// Seams so the orchestration can be unit-tested without network/LLM calls.
    struct Dependencies {
        var fetch: (String) async throws -> ImportedRecipeDraft
        var wouldImprove: (ImportedRecipeDraft) -> Bool
        var cleanUp: (ImportedRecipeDraft) async -> ImportedRecipeDraft
        var reconstruct: (ImportedRecipeDraft) async -> ImportedRecipeDraft
        var inferSteps: (ImportedRecipeDraft) async -> ImportedRecipeDraft
        /// Speech collector for TikTok/YouTube. `failure` explains soft misses.
        var transcribe: (String, ImportedRecipeDraft) async -> (transcript: VideoTranscript?, failure: String?)
        var compileFromSpeech: (ImportedRecipeDraft, VideoTranscript) async -> ImportedRecipeDraft
        var verifySpeech: (ImportedRecipeDraft, VideoTranscript?) -> ImportedRecipeDraft

        static let live = Dependencies(
            fetch: { try await RecipeImportService.importFrom(urlString: $0) },
            wouldImprove: DraftCleanup.wouldImprove,
            cleanUp: { await DraftCleanup.cleanUp($0) },
            reconstruct: { await DraftCleanup.reconstruct($0) },
            inferSteps: { await DraftCleanup.inferSteps($0) },
            transcribe: { url, draft in
                let client = SpeechTranscriptionClient.live
                guard client.isConfigured else {
                    return (nil, "Speech listening isn’t configured in this build")
                }
                // Speech path is for video platforms Scribe can fetch by URL.
                guard draft.platform == .tiktok || draft.platform == .youtube else {
                    return (nil, nil)
                }
                do {
                    let transcript = try await client.transcribe(
                        sourceURL: url,
                        keyterms: SpeechTranscriptionClient.keyterms(from: draft)
                    )
                    return (transcript, nil)
                } catch {
                    let detail = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                    return (nil, detail)
                }
            },
            compileFromSpeech: { draft, transcript in
                await VideoRecipeCompiler.compile(draft, transcript: transcript)
            },
            verifySpeech: { draft, transcript in
                VideoRecipeCompiler.verify(draft, transcript: transcript)
            }
        )
    }

    static func run(
        urlString: String,
        deps: Dependencies = .live,
        progress: @MainActor @escaping (String) -> Void
    ) async throws -> ImportedRecipeDraft {
        await progress("Reading the recipe…")
        var draft = try await deps.fetch(urlString)

        // —— Phase 1 video-first: listen, then compile from caption + speech ——
        var transcript: VideoTranscript?
        if draft.platform == .tiktok || draft.platform == .youtube {
            await progress("Listening to the video…")
            let listened = await deps.transcribe(urlString, draft)
            transcript = listened.transcript
            if let failure = listened.failure, !failure.isEmpty {
                draft.issues.append("Couldn’t listen to the video: \(failure)")
            } else if listened.transcript == nil {
                draft.issues.append("Couldn’t hear enough spoken recipe detail in the video")
            } else if !VideoRecipeCompiler.shouldCompile(transcript: listened.transcript) {
                draft.issues.append("Video audio was too short or quiet to extract a recipe from")
            }
            if VideoRecipeCompiler.shouldCompile(transcript: transcript),
               let transcript {
                await progress("Building the recipe from what was said…")
                draft = await deps.compileFromSpeech(draft, transcript)
                draft = deps.verifySpeech(draft, transcript)
            }
        }

        // Caption/HTML cleanup still helps websites and thin speech results.
        if deps.wouldImprove(draft), !draft.usedSpeechTranscript {
            await progress("Cleaning it up with AI…")
            draft = await deps.cleanUp(draft)
        } else if deps.wouldImprove(draft),
                  draft.usedSpeechTranscript,
                  draft.ingredientLines.isEmpty || draft.stepTexts.isEmpty {
            // Speech path ran but stayed thin — give cleanup a chance with
            // caption + whatever speech produced.
            await progress("Cleaning it up with AI…")
            draft = await deps.cleanUp(draft)
        }

        // Last resort only — never preferred over speech extraction.
        if draft.ingredientLines.isEmpty, draft.isSocialVideo {
            await progress("No recipe in the video — drafting the dish…")
            draft = await deps.reconstruct(draft)
        }
        if draft.stepTexts.isEmpty, !draft.ingredientLines.isEmpty {
            await progress("No method listed — drafting the steps…")
            draft = await deps.inferSteps(draft)
        }
        // No serving count anywhere in the source? Estimate it from the
        // ingredient amounts rather than letting it fall back to a flat "2".
        if draft.servings == nil {
            draft.servings = ServingEstimator.estimate(fromLines: draft.ingredientLines)
        }
        return draft
    }
}
