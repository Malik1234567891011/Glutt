import Foundation

/// One orchestration of the link-import flow, shared by the in-app importer and
/// the share extension: fetch the page, optionally listen to the video, then
/// run the AI passes that improve the draft.
/// `progress` reports the stage, plus the dish name as soon as one is known.
enum ImportPipeline {

    /// What the pipeline is doing right now. The six phases collapse onto the
    /// four status lines the import design uses — the loading screen is not a
    /// step counter, so several phases deliberately read the same.
    enum Stage: String, Sendable {
        case reading
        case listening
        case building
        case cleaning
        /// Nothing usable in the video — the dish is being drafted from scratch.
        case drafting
        /// Ingredients but no method; the steps are being drafted.
        case steps

        /// Plain sentence case, no ellipsis. Any stage can be skipped, so any
        /// label has to be able to follow any other.
        var label: String {
            switch self {
            case .reading:                     "Reading the recipe"
            case .listening:                   "Listening to the video"
            case .building, .drafting, .steps: "Building the recipe"
            case .cleaning:                    "Cleaning it up"
            }
        }
    }

    /// One progress report: where we are, and the best dish name so far.
    struct Progress: Sendable {
        var stage: Stage
        /// `nil` until the source gives up a name — the loading screen shows
        /// skeleton bars until it lands.
        var title: String?
    }

    /// The failure screen's first sentence. The design's line — "Nothing was said
    /// out loud and the caption has no amounts" — is only true for one of these,
    /// so every other reason gets its own. Never claim a cause we didn't hit.
    static func failureReason(for error: Error) -> String {
        switch error {
        case ImportError.nothingFound:
            "Nothing was said out loud and the caption has no amounts."
        case ImportError.instagramBlocked:
            "Instagram doesn’t let apps read this caption, and there was nothing else to go on."
        case ImportError.fetchFailed:
            "That link wouldn’t load, so there was nothing to read."
        case ImportError.invalidURL:
            "That doesn’t look like a link Glutt can open."
        case ImportError.redditNeedsPost:
            "That’s a whole subreddit rather than a single recipe post."
        default:
            (error as? LocalizedError)?.errorDescription ?? "Something went wrong reading this one."
        }
    }

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

    /// Caption/description already has a usable recipe — skip ElevenLabs.
    ///
    /// Checks structured parse first, then the raw caption text. Creators often
    /// paste a full recipe as prose/list that our line parser doesn't fully
    /// structure until the AI cleanup pass; we must still skip listening then.
    static func hasCaptionRecipe(_ draft: ImportedRecipeDraft) -> Bool {
        if hasStructuredCaptionRecipe(draft) { return true }
        return captionTextLooksLikeRecipe(draft)
    }

    /// Already-parsed ingredient lines look like a real list.
    static func hasStructuredCaptionRecipe(_ draft: ImportedRecipeDraft) -> Bool {
        let ingredients = draft.ingredientLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard ingredients.count >= 3 else { return false }

        let withQuantity = ingredients
            .filter { IngredientLineParser.parse($0).quantity != nil }
            .count
        if withQuantity >= 2 { return true }
        if !draft.stepTexts.isEmpty, ingredients.count >= 4 { return true }
        return false
    }

    /// Raw caption/description contains enough quantity/unit signals to treat
    /// as a pasted recipe even when `ingredientLines` is still empty.
    static func captionTextLooksLikeRecipe(_ draft: ImportedRecipeDraft) -> Bool {
        let blob = [draft.caption, draft.title]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        // Thin hooks ("creamiest pasta ever #dinner") never clear this bar.
        guard blob.count >= 80 else { return false }

        // Amount + unit pairs: "2 cups", "1/2 tsp", "½ lb", "200g", "4 cloves"
        let unitHits = amountUnitMatchCount(in: blob)

        let lines = blob
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Lines that already parse as ingredient rows (even mid-caption).
        let lineHits = lines.filter { IngredientLineParser.parse($0).quantity != nil }.count

        // Bullet / numbered ingredient-ish lines.
        let listHits = lines.filter { line in
            guard line.count >= 4, line.count <= 80 else { return false }
            if line.hasPrefix("-") || line.hasPrefix("•") || line.hasPrefix("*") { return true }
            if line.first?.isNumber == true { return true }
            return false
        }.count

        if unitHits >= 3 { return true }
        if lineHits >= 3 { return true }
        if unitHits >= 2, listHits >= 3 { return true }
        return false
    }

    private static let amountUnitRegex: NSRegularExpression = {
        let pattern = #"(?i)(?:\d+\s+\d/\d|\d+/\d|\d+[.,]\d+|\d+|[¼½¾⅓⅔⅛])\s*(?:cups?|tbsps?|tablespoons?|tsps?|teaspoons?|grams?|g\b|kg|mls?|oz|ounces?|lbs?|pounds?|cloves?|pinches?|cans?|packages?|packs?|slices?|bunches?)"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    private static func amountUnitMatchCount(in text: String) -> Int {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return amountUnitRegex.numberOfMatches(in: text, range: range)
    }

    static func run(
        urlString: String,
        deps: Dependencies = .live,
        progress: @MainActor @escaping (Progress) -> Void
    ) async throws -> ImportedRecipeDraft {
        await progress(Progress(stage: .reading, title: nil))
        var draft = try await deps.fetch(urlString)

        // —— Speech only when caption/description is thin ——
        // TikTok/YouTube often paste the full recipe in text. Listening is the
        // expensive path; only use it when the caption didn't already give us one.
        var transcript: VideoTranscript?
        if (draft.platform == .tiktok || draft.platform == .youtube),
           !hasCaptionRecipe(draft) {
            await progress(Progress(stage: .listening, title: draft.title))
            let listened = await deps.transcribe(urlString, draft)
            transcript = listened.transcript
            let captionFallback = (draft.caption ?? "").count >= 60
            // Silent / failed listen is normal when the recipe lives in the caption —
            // don't spam review issues if we still have caption text to work from.
            if !captionFallback {
                if let failure = listened.failure, !failure.isEmpty {
                    draft.issues.append("Couldn’t listen to the video: \(failure)")
                } else if listened.transcript == nil {
                    draft.issues.append("Couldn’t hear enough spoken recipe detail in the video")
                } else if !VideoRecipeCompiler.shouldCompile(transcript: listened.transcript) {
                    draft.issues.append("Video audio was too short or quiet to extract a recipe from")
                }
            }
            if VideoRecipeCompiler.shouldCompile(transcript: transcript),
               let transcript {
                await progress(Progress(stage: .building, title: draft.title))
                draft = await deps.compileFromSpeech(draft, transcript)
                draft = deps.verifySpeech(draft, transcript)
            }
        }

        // Caption/HTML cleanup still helps websites and thin speech results.
        if deps.wouldImprove(draft), !draft.usedSpeechTranscript {
            await progress(Progress(stage: .cleaning, title: draft.title))
            draft = await deps.cleanUp(draft)
        } else if deps.wouldImprove(draft),
                  draft.usedSpeechTranscript,
                  draft.ingredientLines.isEmpty || draft.stepTexts.isEmpty {
            // Speech path ran but stayed thin — give cleanup a chance with
            // caption + whatever speech produced.
            await progress(Progress(stage: .cleaning, title: draft.title))
            draft = await deps.cleanUp(draft)
        }

        // Last resort only — never preferred over speech extraction.
        if draft.ingredientLines.isEmpty, draft.isSocialVideo {
            await progress(Progress(stage: .drafting, title: draft.title))
            draft = await deps.reconstruct(draft)
        }
        if draft.stepTexts.isEmpty, !draft.ingredientLines.isEmpty {
            await progress(Progress(stage: .steps, title: draft.title))
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
