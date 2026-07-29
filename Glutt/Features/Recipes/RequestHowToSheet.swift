import SwiftData
import SwiftUI

/// Lets the user type any cooking basic they want to learn; AI builds a
/// chef-style how-to and saves it into Cooking Basics.
struct RequestHowToSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    /// Called with the inserted lesson after a successful generate.
    var onCreated: (Recipe) -> Void

    @State private var request = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @FocusState private var fieldFocused: Bool

    private static let examples = [
        "how to cook rice",
        "how to make a grilled cheese",
        "how to scramble eggs",
        "how to boil pasta",
        "how to toast bread in a pan",
        "how to cook bacon",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("Ask for any cooking basic — rice, grilled cheese, scrambling eggs. We’ll write it like a chef standing next to you.")
                        .font(.gluttBody)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("What do you want to learn?")
                            .font(.gluttCaption.weight(.semibold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        TextField("e.g. how to cook rice", text: $request, axis: .vertical)
                            .font(.gluttBody)
                            .lineLimit(2...4)
                            .padding(Theme.Spacing.md)
                            .background(Theme.Colors.card)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                    .strokeBorder(Theme.Colors.border, lineWidth: 1)
                            )
                            .focused($fieldFocused)
                            .disabled(isGenerating)
                            .submitLabel(.go)
                            .onSubmit { Task { await generate() } }
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Try one")
                            .font(.gluttCaption.weight(.semibold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        FlowLayout(hSpacing: Theme.Spacing.xs, vSpacing: Theme.Spacing.xs) {
                            ForEach(Self.examples, id: \.self) { example in
                                Button {
                                    Haptics.impact(.light)
                                    request = example
                                } label: {
                                    Text(example)
                                        .font(.gluttCaption.weight(.medium))
                                        .foregroundStyle(Theme.Colors.accent)
                                        .padding(.horizontal, Theme.Spacing.sm)
                                        .padding(.vertical, 8)
                                        .background(Theme.Colors.accent.opacity(0.10))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .disabled(isGenerating)
                            }
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.gluttCaption)
                            .foregroundStyle(Theme.Colors.tomato)
                    }

                    Button {
                        Task { await generate() }
                    } label: {
                        HStack(spacing: 8) {
                            if isGenerating {
                                ProgressView().tint(Theme.Colors.creamText)
                            } else {
                                Ph.sparkle.regular
                                    .resizable().scaledToFit()
                                    .frame(width: 18, height: 18)
                            }
                            Text(isGenerating ? "Writing your how-to…" : "Generate how-to")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.gluttPrimary)
                    .disabled(isGenerating || request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.background)
            .navigationTitle("New how-to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isGenerating)
                }
            }
            .interactiveDismissDisabled(isGenerating)
            .onAppear { fieldFocused = true }
        }
    }

    @MainActor
    private func generate() async {
        let trimmed = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isGenerating else { return }
        errorMessage = nil
        isGenerating = true
        Haptics.impact(.light)
        defer { isGenerating = false }

        do {
            let prefs = UserPrefs.current(in: context)
            let recipe = try await HowToGenerator.generate(request: trimmed, prefs: prefs)
            context.insert(recipe)
            try? context.save()
            Analytics.capture(.recipeCreated, ["source": "ai_howto"])
            Haptics.notify(.success)
            onCreated(recipe)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.notify(.error)
        }
    }
}
