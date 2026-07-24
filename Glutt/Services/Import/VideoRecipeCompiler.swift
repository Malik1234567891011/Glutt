import Foundation

/// Compiles a structured recipe from caption/description + spoken transcript.
///
/// This is Glutt's cooking brain for Phase 1 video import: **extract from
/// evidence**, do not freestyle. Reconstruction (`DraftCleanup.reconstruct`)
/// remains a last resort when speech+caption still yield nothing.
enum VideoRecipeCompiler {

    private struct CompiledDraft: Decodable {
        var title: String?
        var summary: String?
        var servings: Int?
        var prepMinutes: Int?
        var cookMinutes: Int?
        var ingredients: [String]?
        var steps: [String]?
        var tags: [String]?
        /// Fields the model could not resolve from evidence.
        var unresolved: [String]?
        /// Short note on which channels supported the recipe (for issues UI).
        var evidenceNote: String?
    }

    /// True when we have enough speech evidence to prefer this compiler over
    /// caption-only cleanup / reconstruct.
    static func shouldCompile(transcript: VideoTranscript?) -> Bool {
        guard let transcript, !transcript.isEmpty else { return false }
        // ~8+ spoken words — below that Scribe probably failed or the video is silent.
        let spoken = transcript.words.filter(\.isSpokenWord).count
        if spoken >= 8 { return true }
        return transcript.plainText.split(whereSeparator: \.isWhitespace).count >= 12
    }

    /// Merge caption + transcript into a structured draft. On any failure,
    /// returns the input draft unchanged (AI is never load-bearing).
    static func compile(
        _ draft: ImportedRecipeDraft,
        transcript: VideoTranscript,
        client: LLMClient = .live
    ) async -> ImportedRecipeDraft {
        guard client.isConfigured else { return draft }

        let system = """
        You are Glutt's video-recipe compiler. You receive CAPTION/DESCRIPTION text and a \
        TIMESTAMPED SPOKEN TRANSCRIPT from a cooking video. Extract a structured recipe ONLY \
        from that evidence.

        Return JSON only:
        {"title": str, "summary": str, "servings": int|null, "prepMinutes": int|null,
         "cookMinutes": int|null, "ingredients": [str], "steps": [str], "tags": [str],
         "unresolved": [str], "evidenceNote": str}

        STRICT RULES:
        - Prefer SPOKEN quantities and steps when the caption is vague or incomplete.
        - Prefer CAPTION when it has an explicit written ingredient list that the speech lacks.
        - When speech and caption AGREE, use that value. When they CONFLICT on a quantity, pick \
          the more specific written caption value if both are explicit numbers; otherwise put the \
          conflict in "unresolved" (e.g. "soy sauce: speech says 1 tsp, caption says 1 tbsp") and \
          still include ONE best-guess line prefixed with "~".
        - Do NOT invent ingredients that appear in neither caption nor transcript.
        - Do NOT invent exact quantities you did not hear or read. If an ingredient is named with \
          no amount, either omit the amount ("olive oil") or use "~" with a hedged amount only \
          when the speech clearly implies a scale ("a good pour", "a splash") — prefer no amount \
          over a fake precise number.
        - ingredients: one per line, "quantity unit name" when known. KEEP BOTH UNITS when both \
          appear ("0.8 lb (400 g) ground pork"). MERGE duplicates into one total line; split usage \
          across steps.
        - steps: chronological COOKING order (not video edit order — ignore cold-open plated shots). \
          Imperative, one action per step. Include times/temps ONLY when spoken or written; otherwise \
          use doneness cues ("until golden").
        - Mark inferred operational details that weren't in the evidence with "~" or "about".
        - evidenceNote: one short sentence like "Built from spoken quantities + caption title".
        - If evidence is too thin for a real recipe, return {"ingredients": [], "steps": []}.
        """

        var user = ""
        if let title = draft.title { user += "TITLE: \(title)\n" }
        if let creator = draft.creator { user += "CREATOR: \(creator)\n" }
        if let caption = draft.caption, !caption.isEmpty {
            user += "CAPTION_OR_DESCRIPTION:\n\(caption)\n\n"
        } else {
            user += "CAPTION_OR_DESCRIPTION: (empty)\n\n"
        }
        user += "SPOKEN_TRANSCRIPT (timestamped):\n\(transcript.timestampedPlainText())\n"

        // Also give a dense plain transcript so the model doesn't miss amounts
        // if timestamp chunking split mid-phrase.
        user += "\nSPOKEN_TRANSCRIPT_PLAIN:\n\(transcript.plainText)\n"

        do {
            let compiled = try await client.chatJSON(
                CompiledDraft.self,
                system: system,
                user: String(user.prefix(14_000)),
                temperature: 0.2,
                timeout: 45
            )

            guard let ingredients = compiled.ingredients?.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                .filter({ !$0.isEmpty }),
                  !ingredients.isEmpty
            else { return draft }

            var result = draft
            if let title = compiled.title, !title.isEmpty { result.title = title }
            if let summary = compiled.summary, !summary.isEmpty { result.summary = summary }
            if let servings = compiled.servings, servings > 0 { result.servings = servings }
            if let prep = compiled.prepMinutes, prep >= 0 { result.prepMinutes = prep }
            if let cook = compiled.cookMinutes, cook >= 0 { result.cookMinutes = cook }
            result.ingredientLines = ingredients
            if let steps = compiled.steps?.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                .filter({ !$0.isEmpty }), !steps.isEmpty {
                result.stepTexts = steps
                // Steps came from speech/caption evidence — not freestyle invent.
                result.stepsAreAISuggested = false
            }
            if let tags = compiled.tags, !tags.isEmpty {
                result.tags = Array(tags.map { $0.lowercased() }.prefix(6))
            }

            result.speechTranscript = transcript.plainText
            result.speechLanguageCode = transcript.languageCode
            result.usedSpeechTranscript = true

            result.issues.removeAll {
                $0.localizedCaseInsensitiveContains("ingredient")
                    || $0.localizedCaseInsensitiveContains("full recipe")
                    || $0.localizedCaseInsensitiveContains("description didn't")
                    || $0.localizedCaseInsensitiveContains("caption didn't")
                    || $0.localizedCaseInsensitiveContains("drafted this from the video")
                    || $0.localizedCaseInsensitiveContains("Cleaned up with AI")
            }
            let note = compiled.evidenceNote?.trimmingCharacters(in: .whitespacesAndNewlines)
            result.issues.append(
                note?.isEmpty == false
                    ? note!
                    : "Built from the video’s spoken audio + caption — give quantities a once-over"
            )
            if let unresolved = compiled.unresolved?.filter({ !$0.isEmpty }), !unresolved.isEmpty {
                result.issues.append(
                    "Check these: " + unresolved.prefix(4).joined(separator: " · ")
                )
            }
            return result
        } catch {
            return draft
        }
    }

    /// Lightweight evidence check: flags ingredient names that appear in neither
    /// caption nor transcript. Does not rewrite the recipe.
    static func verify(
        _ draft: ImportedRecipeDraft,
        transcript: VideoTranscript?
    ) -> ImportedRecipeDraft {
        guard draft.usedSpeechTranscript, !draft.ingredientLines.isEmpty else { return draft }

        let haystack = (
            (draft.caption ?? "") + " " + (transcript?.plainText ?? draft.speechTranscript ?? "")
        ).lowercased()

        var unsupported: [String] = []
        for line in draft.ingredientLines {
            let parsed = IngredientLineParser.parse(line)
            let name = parsed.name.lowercased()
            // Use the distinctive token(s) — skip ultra-generic words.
            let tokens = name
                .split(whereSeparator: { !$0.isLetter && $0 != "-" })
                .map(String.init)
                .filter { $0.count >= 4 && !["fresh", "large", "small", "chopped", "minced", "optional"].contains($0) }
            guard let anchor = tokens.max(by: { $0.count < $1.count }) else { continue }
            if !haystack.contains(anchor) {
                unsupported.append(parsed.name)
            }
        }

        guard !unsupported.isEmpty else { return draft }
        var result = draft
        let list = unsupported.prefix(5).joined(separator: ", ")
        result.issues.append("Couldn’t clearly hear/read: \(list) — confirm those")
        return result
    }
}
