import SwiftData
import SwiftUI

/// Review and correct an imported draft before saving it as a recipe.
/// Trust is the product: show confidence, flag issues, allow inline edits.
struct ImportReviewView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RecipeCollection.createdAt) private var collections: [RecipeCollection]

    let onDone: () -> Void

    @State private var draft: ImportedRecipeDraft
    @State private var title: String
    @State private var servings: Int
    @State private var prepMinutes: Int
    @State private var cookMinutes: Int
    @State private var ingredientLines: [EditableLine]
    @State private var stepLines: [EditableLine]
    @State private var selectedCollections: Set<PersistentIdentifier> = []

    struct EditableLine: Identifiable {
        let id = UUID()
        var text: String
    }

    init(draft: ImportedRecipeDraft, onDone: @escaping () -> Void) {
        self.onDone = onDone
        _draft = State(initialValue: draft)
        _title = State(initialValue: draft.title ?? "")
        _servings = State(initialValue: draft.servings ?? 2)
        _prepMinutes = State(initialValue: draft.prepMinutes ?? 0)
        _cookMinutes = State(initialValue: draft.cookMinutes ?? 0)
        _ingredientLines = State(initialValue: draft.ingredientLines.map { EditableLine(text: $0) })
        _stepLines = State(initialValue: draft.stepTexts.map { EditableLine(text: $0) })
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && ingredientLines.contains { !$0.text.isEmpty }
            && stepLines.contains { !$0.text.isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                confidenceHeader
                if !draft.issues.isEmpty {
                    issuesCard
                }
                previewCard
                basicsCard
                ingredientsCard
                stepsCard
                if !collections.isEmpty {
                    collectionsCard
                }

                Button("Save recipe") { save() }
                    .buttonStyle(.gluttPrimary)
                    .disabled(!canSave)
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Colors.background)
    }

    // MARK: - Sections

    /// Optional, pre-save: tap to toggle. No dialog, no pressure.
    private var collectionsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("ADD TO A COLLECTION — OPTIONAL")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(collections) { collection in
                        let isSelected = selectedCollections.contains(collection.persistentModelID)
                        Button {
                            if isSelected {
                                selectedCollections.remove(collection.persistentModelID)
                            } else {
                                selectedCollections.insert(collection.persistentModelID)
                            }
                        } label: {
                            Chip(label: collection.name, isSelected: isSelected)
                                .fixedSize()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .cardStyle()
    }

    private var confidenceHeader: some View {
        HStack {
            ConfidenceBadge(confidence: draft.confidence)
            Spacer()
            if let source = draft.sourceURL, let url = URL(string: source), let host = url.host {
                Label(host, systemImage: "link")
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    private var issuesCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(draft.issues, id: \.self) { issue in
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.warning)
                    Text(issue)
                        .font(.gluttCaption)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.warningTint)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    @ViewBuilder
    private var previewCard: some View {
        if let imageURL = draft.imageURL, let url = URL(string: imageURL) {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(Theme.Colors.accent.opacity(0.08))
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
    }

    private var basicsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            TextField("Recipe title", text: $title)
                .font(.gluttTitle)
            if let creator = draft.creator {
                Text("by \(creator)")
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Divider()
            Stepper("Servings: \(servings)", value: $servings, in: 1...24)
            Stepper("Prep: \(prepMinutes) min", value: $prepMinutes, in: 0...240, step: 5)
            Stepper("Cook: \(cookMinutes) min", value: $cookMinutes, in: 0...480, step: 5)
        }
        .font(.gluttBody)
        .cardStyle()
    }

    private var ingredientsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Ingredients")
            ForEach($ingredientLines) { $line in
                HStack {
                    parseBadge(for: line.text)
                    TextField("Ingredient", text: $line.text)
                        .font(.gluttBody)
                }
            }
            Button("Add ingredient", systemImage: "plus") {
                ingredientLines.append(EditableLine(text: ""))
            }
            .font(.gluttCaption.weight(.medium))
            .foregroundStyle(Theme.Colors.accent)
        }
        .cardStyle()
    }

    /// Green check when the line parsed into qty+name, amber dot when it's a guess.
    private func parseBadge(for line: String) -> some View {
        let parsed = IngredientLineParser.parse(line)
        let isClean = parsed.quantity != nil && !parsed.name.isEmpty
        return Image(systemName: isClean ? "checkmark.circle.fill" : "circle.dotted")
            .font(.caption)
            .foregroundStyle(isClean ? Theme.Colors.accent : Theme.Colors.warning)
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Steps")
            ForEach(Array($stepLines.enumerated()), id: \.element.id) { index, $line in
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Text("\(index + 1).")
                        .font(.gluttCaption.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    TextField("Step", text: $line.text, axis: .vertical)
                        .font(.gluttBody)
                }
            }
            Button("Add step", systemImage: "plus") {
                stepLines.append(EditableLine(text: ""))
            }
            .font(.gluttCaption.weight(.medium))
            .foregroundStyle(Theme.Colors.accent)
        }
        .cardStyle()
    }

    // MARK: - Save

    private func save() {
        let recipe = Recipe(
            title: title.trimmingCharacters(in: .whitespaces),
            summary: draft.summary,
            sourceCreator: draft.creator,
            sourceURL: draft.sourceURL,
            sourcePlatform: draft.platform,
            sourceCaption: draft.caption,
            importedAt: .now,
            importConfidence: draft.confidence,
            imageURL: draft.imageURL,
            servings: servings,
            prepMinutes: prepMinutes,
            cookMinutes: cookMinutes,
            tags: draft.tags
        )
        recipe.calories = draft.calories
        recipe.proteinGrams = draft.proteinGrams

        recipe.ingredients = ingredientLines
            .map { $0.text.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { index, line in
                let parsed = IngredientLineParser.parse(line)
                return RecipeIngredient(
                    name: parsed.name,
                    quantity: parsed.quantity,
                    unit: parsed.unit,
                    note: parsed.note,
                    sortIndex: index
                )
            }

        recipe.steps = stepLines
            .map { $0.text.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { index, text in
                RecipeStep(index: index, text: text, durationSeconds: detectDuration(in: text))
            }

        context.insert(recipe)
        for collection in collections where selectedCollections.contains(collection.persistentModelID) {
            collection.recipes.append(recipe)
        }
        onDone()
    }

    /// "simmer for 10 minutes" -> 600 seconds. Powers Cook Mode timers later.
    private func detectDuration(in text: String) -> Int? {
        let pattern = #"(\d+)\s*(?:-\s*\d+\s*)?(minutes|minute|mins|min|hours|hour|hrs|hr)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let numberRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let value = Int(text[numberRange])
        else { return nil }
        let unit = text[unitRange].lowercased()
        return unit.hasPrefix("h") ? value * 3600 : value * 60
    }
}
