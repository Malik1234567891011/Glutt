import SwiftData
import SwiftUI

/// The Polly tab: what Polly knows about your kitchen, a recipe picker that
/// launches a live cooking session, and the recent-cooks log. When the AI
/// service isn't configured the tab degrades to a single setup card (house
/// `LLMClient.isConfigured` convention).
struct PollyTabView: View {
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
    @Query(sort: \PollyCookLog.startedAt, order: .reverse) private var cookLogs: [PollyCookLog]
    @Query private var pantryItems: [PantryItem]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                header
                if LLMClient.isConfigured {
                    memoryCard
                    cookSection
                    recentCooksSection
                } else {
                    setupCard
                }
            }
            .padding(Theme.Spacing.md)
        }
        .contentMargins(.bottom, GluttTabBar.reservedHeight, for: .scrollContent)
        .background(Theme.Colors.background)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Polly")
                .font(.gluttLargeTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Your live cooking chef")
                .font(.gluttCaption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    // MARK: - Setup card (AI not configured)

    private var setupCard: some View {
        EmptyStateView(
            icon: "sparkles",
            title: "Polly needs the AI service",
            message: "This build isn't connected to Glutt's AI yet, so live cooking sessions are unavailable. Your recipes and Cook Mode still work everywhere else."
        )
        .padding(.top, Theme.Spacing.xl)
    }

    // MARK: - What Polly knows

    private var memoryCount: Int {
        (try? context.fetchCount(FetchDescriptor<PollyMemory>())) ?? 0
    }

    private var memoryCard: some View {
        let facts = PollyMemoryStore.topFacts(limit: 3, in: context)
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("What Polly knows")
                    .font(.gluttHeadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                if memoryCount > 0 {
                    Text(memoryCount == 1 ? "1 kitchen note" : "\(memoryCount) kitchen notes")
                        .font(.gluttCaption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            if facts.isEmpty {
                Text("Polly learns your kitchen every time you cook together.")
                    .font(.gluttBody)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    ForEach(facts) { fact in
                        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                            Circle()
                                .fill(Theme.Colors.accent)
                                .frame(width: 5, height: 5)
                                .padding(.top, 7)
                            Text(fact.text)
                                .font(.gluttBody)
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Cook something together

    @ViewBuilder
    private var cookSection: some View {
        SectionHeader(title: "Cook something together")
        if recipes.isEmpty {
            EmptyStateView(
                icon: "book",
                title: "No recipes yet",
                message: "Save a recipe first — share one from TikTok or paste a link.",
                actionLabel: "Import a recipe",
                action: { router.perform(.importRecipe) }
            )
        } else {
            ForEach(recipes.prefix(20)) { recipe in
                let match = PantryMatcher.match(recipe: recipe, pantry: pantryItems)
                Button {
                    Haptics.impact(.medium)
                    PollyPaywallHook.run {
                        router.pollyLaunch = PollyLaunch(recipe: recipe, scale: 1)
                    }
                } label: {
                    RecipeCard(recipe: recipe, pantryMatch: (match.ownedCount, match.totalCount))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Starts a live cooking session with Polly")
            }
        }
    }

    // MARK: - Recent cooks with Polly

    @ViewBuilder
    private var recentCooksSection: some View {
        if !cookLogs.isEmpty {
            SectionHeader(title: "Recent cooks with Polly")
            let recent = Array(cookLogs.prefix(5))
            VStack(spacing: 0) {
                ForEach(recent) { log in
                    cookLogRow(log)
                    if log !== recent.last {
                        Divider().overlay(Theme.Colors.border)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .cardStyle(padding: Theme.Spacing.xs)
        }
    }

    private func cookLogRow(_ log: PollyCookLog) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Ph.chefHat.regular
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(Theme.Colors.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(logTitle(log))
                    .font(.gluttBody)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Text(log.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            Text("\(log.stepsCompleted)/\(log.stepsTotal) steps")
                .font(.gluttCaption.weight(.medium))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.vertical, Theme.Spacing.sm)
    }

    private func logTitle(_ log: PollyCookLog) -> String {
        if let title = log.recipe?.title, !title.isEmpty { return title }
        if !log.summary.isEmpty { return String(log.summary.prefix(60)) }
        return "Cooking session"
    }
}

#Preview {
    PollyTabView()
        .environment(Router())
        .modelContainer(for: [Recipe.self, PantryItem.self, PollyMemory.self, PollyCookLog.self], inMemory: true)
}
