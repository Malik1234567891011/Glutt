import SwiftData
import SwiftUI

/// Invent an original recipe from on-hand kitchen ingredients. Opened from
/// Kitchen — not a home-tab dashboard card. Result flows through the normal
/// import review → save path and is labeled as Glutt-invented.
struct InventDishView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var pantryItems: [PantryItem]

    @State private var isInventing = false
    @State private var inventMealType: MealType?
    @State private var inventHint = ""
    @State private var inventedDraft: ImportedRecipeDraft?
    @State private var reviewDraft: ImportedRecipeDraft?
    @State private var inventedTitles: [String] = []
    @State private var inventError: String?

    private var onHandItems: [PantryItem] {
        pantryItems.filter { $0.roughQuantity != .out }
    }

    private var canInvent: Bool {
        LLMClient.isConfigured && onHandItems.count >= 2
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    if !LLMClient.isConfigured {
                        EmptyStateView(
                            icon: "sparkles",
                            title: "Invention needs Glutt’s AI",
                            message: "This build isn’t connected yet, so dish invention is unavailable."
                        )
                    } else if !canInvent {
                        EmptyStateView(
                            icon: "refrigerator",
                            title: "Add a couple of ingredients first",
                            message: "Once your kitchen has a few things on hand, Glutt can invent a dish around them."
                        )
                    } else {
                        inventBody
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Invent a dish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $reviewDraft) { draft in
                NavigationStack {
                    ImportReviewView(draft: draft) {
                        reviewDraft = nil
                        inventedDraft = nil
                        dismiss()
                    }
                    .navigationTitle("Your new recipe")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { reviewDraft = nil }
                        }
                    }
                }
            }
            .alert("Couldn't invent a dish", isPresented: Binding(
                get: { inventError != nil },
                set: { if !$0 { inventError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(inventError ?? "")
            }
        }
    }

    private var inventBody: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("A brand-new recipe built around \(pantryPreview) — not one of your saved ones.")
                .font(.gluttBody)
                .foregroundStyle(Theme.Colors.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    selectableChip("Any", isSelected: inventMealType == nil) {
                        inventMealType = nil
                    }
                    ForEach(MealType.allCases) { type in
                        selectableChip(type.label, isSelected: inventMealType == type) {
                            inventMealType = type
                        }
                    }
                }
            }

            TextField("Optional: “feed 4”, “something light”, “quick”", text: $inventHint, axis: .vertical)
                .font(.gluttBody)
                .lineLimit(1...2)
                .padding(Theme.Spacing.sm)
                .background(Theme.Colors.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))

            Button {
                Haptics.impact(.medium)
                invent(excludingCurrent: false)
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    if isInventing { ProgressView().tint(.white) }
                    Text(isInventing ? "Cooking up an idea…" : "Make something new")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.gluttPrimary)
            .disabled(isInventing)

            if let draft = inventedDraft {
                inventedPreview(draft)
            }
        }
    }

    private func inventedPreview(_ draft: ImportedRecipeDraft) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(draft.title ?? "New dish")
                .font(.gluttHeadline)
                .foregroundStyle(Theme.Colors.textPrimary)
            if let summary = draft.summary, !summary.isEmpty {
                Text(summary)
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            HStack(spacing: Theme.Spacing.md) {
                if let servings = draft.servings {
                    Label("\(servings) servings", systemImage: "person.2")
                }
                let mins = (draft.prepMinutes ?? 0) + (draft.cookMinutes ?? 0)
                if mins > 0 {
                    Label("\(mins) min", systemImage: "clock")
                }
            }
            .font(.gluttCaption)
            .foregroundStyle(Theme.Colors.textSecondary)

            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    reviewDraft = draft
                } label: {
                    Text("Save this recipe")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.gluttSecondary)

                Button {
                    invent(excludingCurrent: true)
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        if isInventing { ProgressView() }
                        Text("Something else")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.gluttSecondary)
                .disabled(isInventing)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var pantryPreview: String {
        let names = onHandItems
            .sorted { ($0.useSoonDate != nil ? 0 : 1) < ($1.useSoonDate != nil ? 0 : 1) }
            .prefix(3)
            .map { $0.name.lowercased() }
        switch names.count {
        case 0: return "what you have"
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return "\(names[0]), \(names[1]), and more"
        }
    }

    private func invent(excludingCurrent: Bool) {
        guard !isInventing else { return }
        if excludingCurrent, let current = inventedDraft?.title {
            if !inventedTitles.contains(current) { inventedTitles.append(current) }
        }
        isInventing = true
        let prefs = UserPrefs.current(in: context)
        let hint = inventHint.trimmingCharacters(in: .whitespacesAndNewlines)
        let avoid = Array(inventedTitles.suffix(6))
        Task {
            let draft = await PantryChef.invent(
                pantry: pantryItems,
                prefs: prefs,
                hint: hint.isEmpty ? nil : hint,
                maxMinutes: nil,
                mealType: inventMealType,
                avoidTitles: avoid
            )
            isInventing = false
            if let draft {
                Haptics.notify(.success)
                inventedDraft = draft
                if let title = draft.title, !inventedTitles.contains(title) {
                    inventedTitles.append(title)
                }
            } else {
                inventError = "Glutt couldn’t spin up a dish from your pantry right now. Add a few more items, or try again."
            }
        }
    }

    private func selectableChip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.gluttCaption.weight(.medium))
                .foregroundStyle(isSelected ? Theme.Colors.creamText : Theme.Colors.textPrimary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Capsule().fill(isSelected ? Theme.Colors.accent : Theme.Colors.card))
                .overlay(isSelected ? nil : Capsule().strokeBorder(Theme.Colors.textPrimary.opacity(0.08), lineWidth: 1.5))
                .fixedSize()
        }
        .buttonStyle(.plain)
    }
}
