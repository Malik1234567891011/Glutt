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
                if draft.isAIGenerated {
                    inventedBanner
                } else {
                    confidenceHeader
                }
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

                Button("Save recipe") {
                    Haptics.impact(.medium)
                    save()
                }
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
                            Haptics.selection()
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

    private var inventedBanner: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Ph.sparkle.fill
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundStyle(Theme.Colors.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Glutt invented this from what you have")
                    .font(.gluttHeadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("It's a fresh idea, not one of your saved recipes. Read it over, adjust amounts, and make it yours.")
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.accent.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var confidenceHeader: some View {
        HStack {
            ConfidenceBadge(confidence: draft.confidence)
            Spacer()
            if let source = draft.sourceURL, let url = URL(string: source), let host = url.host {
                HStack(spacing: 4) {
                    Ph.link.regular
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                    Text(host)
                }
                .font(.gluttCaption)
                .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    private var issuesCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(draft.issues, id: \.self) { issue in
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Ph.warning.fill
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
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
                .hapticOnChange(of: servings)
            Stepper("Prep: \(prepMinutes) min", value: $prepMinutes, in: 0...240, step: 5)
                .hapticOnChange(of: prepMinutes)
            Stepper("Cook: \(cookMinutes) min", value: $cookMinutes, in: 0...480, step: 5)
                .hapticOnChange(of: cookMinutes)
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
            Button {
                Haptics.impact(.light)
                ingredientLines.append(EditableLine(text: ""))
            } label: {
                HStack(spacing: 4) {
                    Ph.plus.regular
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                    Text("Add ingredient")
                }
            }
            .font(.gluttCaption.weight(.medium))
            .foregroundStyle(Theme.Colors.accent)
        }
        .cardStyle()
    }

    /// Green check when the line parsed into qty+name, amber dot when it's a guess.
    @ViewBuilder
    private func parseBadge(for line: String) -> some View {
        let parsed = IngredientLineParser.parse(line)
        let isClean = parsed.quantity != nil && !parsed.name.isEmpty
        if isClean {
            Ph.checkCircle.fill
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .foregroundStyle(Theme.Colors.accent)
        } else {
            Ph.circleDashed.regular
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .foregroundStyle(Theme.Colors.warning)
        }
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Steps")
            if draft.stepsAreAISuggested {
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Ph.sparkle.fill
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundStyle(Theme.Colors.accent)
                    Text("The source had no method, so Glutt drafted these from the dish and ingredients. Give them a read and tweak anything off.")
                        .font(.gluttCaption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .padding(Theme.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Colors.accent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
            }
            ForEach(Array($stepLines.enumerated()), id: \.element.id) { index, $line in
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Text("\(index + 1).")
                        .font(.gluttCaption.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    TextField("Step", text: $line.text, axis: .vertical)
                        .font(.gluttBody)
                }
            }
            Button {
                Haptics.impact(.light)
                stepLines.append(EditableLine(text: ""))
            } label: {
                HStack(spacing: 4) {
                    Ph.plus.regular
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                    Text("Add step")
                }
            }
            .font(.gluttCaption.weight(.medium))
            .foregroundStyle(Theme.Colors.accent)
        }
        .cardStyle()
    }

    // MARK: - Save

    private func save() {
        var edited = draft
        edited.title = title.trimmingCharacters(in: .whitespaces)
        edited.servings = servings
        edited.prepMinutes = prepMinutes
        edited.cookMinutes = cookMinutes
        edited.ingredientLines = ingredientLines.map(\.text)
        edited.stepTexts = stepLines.map(\.text)

        let recipe = RecipeFactory.make(from: edited)
        context.insert(recipe)
        for collection in collections where selectedCollections.contains(collection.persistentModelID) {
            collection.recipes.append(recipe)
        }
        onDone()
    }
}
