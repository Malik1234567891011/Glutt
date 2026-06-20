import PhotosUI
import PhosphorSwift
import SwiftData
import SwiftUI

/// Create or edit a recipe. Edits are staged in local state and only
/// written to the model on Save, so Cancel is always safe.
struct RecipeEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Nil creates a new recipe.
    let recipe: Recipe?

    @State private var title = ""
    @State private var summary = ""
    @State private var servings = 2
    @State private var prepMinutes = 10
    @State private var cookMinutes = 20
    @State private var difficulty: Difficulty = .beginner
    @State private var tagsText = ""
    @State private var ingredients: [IngredientDraft] = [IngredientDraft()]
    @State private var steps: [StepDraft] = [StepDraft()]
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?

    struct IngredientDraft: Identifiable {
        let id = UUID()
        var name = ""
        var quantityText = ""
        var unit = ""
        var isOptional = false
    }

    struct StepDraft: Identifiable {
        let id = UUID()
        var text = ""
        var minutesText = ""
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && ingredients.contains { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            && steps.contains { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                basicsSection
                photoSection
                ingredientsSection
                stepsSection
                tagsSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .navigationTitle(recipe == nil ? "New recipe" : "Edit recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Haptics.notify(.warning)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: loadExisting)
            .onChange(of: photoItem) {
                Task {
                    photoData = try? await photoItem?.loadTransferable(type: Data.self)
                }
            }
            .onChange(of: difficulty) {
                Haptics.selection()
            }
            .onChange(of: servings) {
                Haptics.impact(.light)
            }
            .onChange(of: prepMinutes) {
                Haptics.impact(.light)
            }
            .onChange(of: cookMinutes) {
                Haptics.impact(.light)
            }
        }
    }

    // MARK: - Sections

    private var basicsSection: some View {
        Section("Basics") {
            TextField("Title", text: $title)
            TextField("Short description (optional)", text: $summary, axis: .vertical)
            Stepper("Servings: \(servings)", value: $servings, in: 1...24)
            Stepper("Prep: \(prepMinutes) min", value: $prepMinutes, in: 0...240, step: 5)
            Stepper("Cook: \(cookMinutes) min", value: $cookMinutes, in: 0...480, step: 5)
            Picker("Difficulty", selection: $difficulty) {
                ForEach(Difficulty.allCases) { level in
                    Text(level.label).tag(level)
                }
            }
        }
    }

    private var photoSection: some View {
        Section("Photo") {
            PhotosPicker(selection: $photoItem, matching: .images) {
                if let photoData, let uiImage = UIImage(data: photoData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 140)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                } else {
                    HStack(spacing: Theme.Spacing.sm) {
                        Ph.image.regular
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .foregroundStyle(Theme.Colors.accent)
                        Text("Choose a photo")
                            .font(.gluttBody)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                }
            }
        }
    }

    private var ingredientsSection: some View {
        Section("Ingredients") {
            ForEach($ingredients) { $draft in
                HStack {
                    TextField("Ingredient", text: $draft.name)
                    TextField("Qty", text: $draft.quantityText)
                        .keyboardType(.decimalPad)
                        .frame(width: 50)
                    TextField("Unit", text: $draft.unit)
                        .frame(width: 60)
                }
            }
            .onDelete { offsets in
                Haptics.notify(.warning)
                ingredients.remove(atOffsets: offsets)
            }
            Button {
                Haptics.impact(.light)
                ingredients.append(IngredientDraft())
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Ph.plus.regular
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(Theme.Colors.accent)
                    Text("Add ingredient")
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
        }
    }

    private var stepsSection: some View {
        Section("Steps") {
            ForEach(Array($steps.enumerated()), id: \.element.id) { index, $draft in
                HStack(alignment: .top) {
                    Text("\(index + 1).")
                        .foregroundStyle(Theme.Colors.textSecondary)
                    TextField("What to do", text: $draft.text, axis: .vertical)
                    TextField("min", text: $draft.minutesText)
                        .keyboardType(.numberPad)
                        .frame(width: 44)
                }
            }
            .onDelete { offsets in
                Haptics.notify(.warning)
                steps.remove(atOffsets: offsets)
            }
            Button {
                Haptics.impact(.light)
                steps.append(StepDraft())
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Ph.plus.regular
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(Theme.Colors.accent)
                    Text("Add step")
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
        }
    }

    private var tagsSection: some View {
        Section("Tags") {
            TextField("Comma separated: Dinner, High protein, Quick", text: $tagsText)
        }
    }

    // MARK: - Load & save

    private func loadExisting() {
        guard let recipe else { return }
        title = recipe.title
        summary = recipe.summary ?? ""
        servings = recipe.servings
        prepMinutes = recipe.prepMinutes
        cookMinutes = recipe.cookMinutes
        difficulty = recipe.difficulty
        tagsText = recipe.tags.joined(separator: ", ")
        photoData = recipe.imageData
        ingredients = recipe.ingredients
            .sorted { $0.sortIndex < $1.sortIndex }
            .map { ingredient in
                var draft = IngredientDraft()
                draft.name = ingredient.name
                draft.quantityText = ingredient.quantity.map { UnitConverter.format(quantity: $0) } ?? ""
                draft.unit = ingredient.unit ?? ""
                draft.isOptional = ingredient.isOptional
                return draft
            }
        steps = recipe.sortedSteps.map { step in
            var draft = StepDraft()
            draft.text = step.text
            draft.minutesText = step.durationSeconds.map { "\($0 / 60)" } ?? ""
            return draft
        }
    }

    private func save() {
        Haptics.notify(.success)
        let target: Recipe
        if let recipe {
            target = recipe
        } else {
            target = Recipe(title: title)
            context.insert(target)
        }

        target.title = title.trimmingCharacters(in: .whitespaces)
        target.summary = summary.isEmpty ? nil : summary
        target.servings = servings
        target.prepMinutes = prepMinutes
        target.cookMinutes = cookMinutes
        target.difficulty = difficulty
        target.tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let photoData {
            target.imageData = photoData
            target.imageAssetName = nil
        }

        target.ingredients = ingredients
            .filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            .enumerated()
            .map { index, draft in
                RecipeIngredient(
                    name: draft.name.trimmingCharacters(in: .whitespaces),
                    quantity: parseQuantity(draft.quantityText),
                    unit: draft.unit.isEmpty ? nil : draft.unit,
                    isOptional: draft.isOptional,
                    sortIndex: index
                )
            }

        target.steps = steps
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .enumerated()
            .map { index, draft in
                RecipeStep(
                    index: index,
                    text: draft.text.trimmingCharacters(in: .whitespaces),
                    durationSeconds: Int(draft.minutesText).map { $0 * 60 }
                )
            }

        dismiss()
    }

    private func parseQuantity(_ text: String) -> Double? {
        let glyphs: [String: Double] = ["¼": 0.25, "⅓": 0.333, "½": 0.5, "⅔": 0.666, "¾": 0.75]
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let direct = Double(trimmed) { return direct }
        // Handle "1½" style input.
        for (glyph, value) in glyphs where trimmed.hasSuffix(glyph) {
            let wholePart = String(trimmed.dropLast())
            let whole = wholePart.isEmpty ? 0 : (Double(wholePart) ?? 0)
            return whole + value
        }
        return nil
    }
}
