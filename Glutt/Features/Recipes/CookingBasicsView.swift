import SwiftData
import SwiftUI

/// Full list of Cooking Basics lessons — technique how-tos that teach you to cook.
struct CookingBasicsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Recipe.createdAt) private var allRecipes: [Recipe]

    /// Opens a lesson in the parent Recipes stack.
    ///
    /// Not optional, and not a `NavigationLink`. This screen is presented as a
    /// sheet wrapping its own bare `NavigationStack`, and the
    /// `navigationDestination(for: Recipe.self)` that resolves a recipe lives in
    /// the Recipes stack outside the sheet. A `NavigationLink(value:)` with no
    /// matching destination in its own stack renders inert, which is why every
    /// lesson row here was unpressable. Requiring the closure means a future
    /// caller can't reintroduce a dead row by omitting it.
    var onOpenLesson: (Recipe) -> Void

    @State private var isRequestingHowTo = false

    private var lessons: [Recipe] {
        allRecipes.filter { $0.parentRecipe == nil && $0.isCookingBasic }
            .sorted { $0.title < $1.title }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Short lessons that feel like a chef standing next to you — what to grab, what to look for, and exactly what “done” looks like. Ask for anything you don’t know how to do.")
                    .font(.gluttBody)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.horizontal, Theme.Spacing.md)

                if LLMClient.isConfigured {
                    Button {
                        Haptics.impact(.light)
                        isRequestingHowTo = true
                    } label: {
                        HStack(spacing: Theme.Spacing.md) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(Theme.Colors.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Ask for a how-to")
                                    .font(.gluttHeadline)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Text("Type anything — rice, grilled cheese, bacon…")
                                    .font(.gluttCaption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            Spacer(minLength: 0)
                            Ph.sparkle.regular
                                .resizable().scaledToFit()
                                .frame(width: 18, height: 18)
                                .foregroundStyle(Theme.Colors.accent)
                        }
                        .padding(Theme.Spacing.md)
                        .background(Theme.Colors.accent.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                .strokeBorder(Theme.Colors.accent.opacity(0.25), lineWidth: 1)
                        )
                        .padding(.horizontal, Theme.Spacing.md)
                    }
                    .buttonStyle(.plain)
                }

                ForEach(lessons) { lesson in
                    Button {
                        Haptics.impact(.light)
                        onOpenLesson(lesson)
                    } label: {
                        lessonCard(lesson)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, Theme.Spacing.md)
        }
        .contentMargins(.bottom, GluttTabBar.reservedHeight, for: .scrollContent)
        .background(Theme.Colors.background)
        .navigationTitle("Cooking basics")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $isRequestingHowTo) {
            RequestHowToSheet { recipe in
                onOpenLesson(recipe)
            }
        }
    }

    private func lessonCard(_ lesson: Recipe) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            RecipeImageView(recipe: lesson)
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.photo, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(lesson.title)
                    .font(.gluttHeadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.leading)
                if let summary = lesson.summary {
                    Text(summary)
                        .font(.gluttCaption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                HStack(spacing: 8) {
                    StatPill.time(lesson.timeLabel)
                    StatPill.difficulty(lesson.difficulty.label)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .padding(.horizontal, Theme.Spacing.md)
    }
}
