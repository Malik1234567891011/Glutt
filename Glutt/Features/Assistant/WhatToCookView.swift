import SwiftData
import SwiftUI

/// "Invent a dish from what I have" — Glutt spins up an original recipe built
/// around the user's on-hand ingredients. Search and recommendations now live
/// on the Recipes page; this sheet does invention only.
struct WhatToCookView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var pantryItems: [PantryItem]

    @State private var isInventing = false
    @State private var inventMealType: MealType?
    @State private var inventHint = ""
    /// The current inline idea shown for review before saving.
    @State private var inventedDraft: ImportedRecipeDraft?
    /// Separate handle for the full review/save sheet.
    @State private var reviewDraft: ImportedRecipeDraft?
    /// Titles proposed this session, so "Something else" never repeats them.
    @State private var inventedTitles: [String] = []
    @State private var inventError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    if LLMClient.isConfigured {
                        inventCard
                    } else {
                        aiOffNotice
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

    private var aiOffNotice: some View {
        EmptyStateView(
            icon: "sparkles",
            title: "Invention needs the AI service",
            message: "This build isn't connected to Glutt's AI yet, so dish invention is unavailable. You can still browse and search your recipes on the Recipes tab."
        )
    }

    // MARK: - Invent from pantry

    private var onHandItems: [PantryItem] {
        pantryItems.filter { $0.roughQuantity != .out }
    }

    private var canInvent: Bool {
        LLMClient.isConfigured && onHandItems.count >= 2
    }

    private var inventCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Ph.magicWand.regular
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(canInvent ? Theme.Colors.accent : Theme.Colors.textSecondary)
                Text("Invent a dish from what I have")
                    .font(.gluttHeadline)
                    .foregroundStyle(canInvent ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
            }

            if canInvent {
                Text("A brand-new recipe built around your \(pantryPreview) — not one of your saved ones.")
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                inventControls

                if let draft = inventedDraft {
                    inventedPreview(draft)
                }
            } else {
                Text("Add a couple of things to your kitchen and Glutt will spin up an original recipe from what you have.")
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Button {
                } label: {
                    Text("Make something new")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.gluttPrimary)
                .disabled(true)
            }
        }
        .cardStyle()
    }

    /// Meal-type chips + an optional free-text steer, then the generate button.
    private var inventControls: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
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

            TextField("Optional: \"feed 4\", \"something light\", \"quick & easy\"", text: $inventHint, axis: .vertical)
                .font(.gluttBody)
                .lineLimit(1...2)
                .padding(Theme.Spacing.sm)
                .background(Theme.Colors.background)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))

            Button {
                Haptics.impact(.medium)
                invent(excludingCurrent: false)
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    if isInventing { ProgressView().tint(.white) }
                    Text(isInventing ? "Cooking up an idea\u{2026}" : "Make something new")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.gluttPrimary)
            .disabled(isInventing)
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
        .background(Theme.Colors.background)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var pantryPreview: String {
        let names = onHandItems
            .sorted { ($0.useSoonDate != nil ? 0 : 1) < ($1.useSoonDate != nil ? 0 : 1) }
            .prefix(3)
            .map { $0.name.lowercased() }
        switch names.count {
        case 0: return "ingredients"
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return "\(names[0]), \(names[1]), and more"
        }
    }

    /// - Parameter excludingCurrent: when true (the "Something else" path), the
    ///   dish currently on screen is added to the avoid-list so the model is
    ///   forced to return a clearly different idea.
    private func invent(excludingCurrent: Bool) {
        guard !isInventing else { return }
        if excludingCurrent, let current = inventedDraft?.title {
            if !inventedTitles.contains(current) { inventedTitles.append(current) }
        }
        // Premium gate: AI recipe invention is a paid feature (currently open for
        // the free launch). The hook runs the block immediately when ungated.
        InventionPaywallHook.presentBeforeInventing {
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
                    inventError = "Glutt couldn't spin up a dish from your pantry right now. Add a few more items, or try again."
                }
            }
        }
    }

    private func selectableChip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.gluttCaption.weight(.medium))
                .foregroundStyle(isSelected ? .white : Theme.Colors.textPrimary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(isSelected ? Theme.Colors.accent : Theme.Colors.accent.opacity(0.08))
                .clipShape(Capsule())
                .fixedSize()
        }
        .buttonStyle(.plain)
    }
}
