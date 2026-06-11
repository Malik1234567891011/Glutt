import SwiftData
import SwiftUI

/// Phase 0 placeholder. Full cooking stats and optional gym mode arrive in Phase 7.
struct ProgressTabView: View {
    @Query private var sessions: [CookSession]
    @Query private var recipes: [Recipe]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    HStack(spacing: Theme.Spacing.md) {
                        statCard(value: "\(sessions.count)", label: "Meals cooked")
                        statCard(value: "\(recipes.count)", label: "Recipes saved")
                    }

                    EmptyStateView(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Progress lives here",
                        message: "Cooking stats by default. Calories and protein only if you turn on Gym Mode — never forced."
                    )
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Progress")
        }
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(value)
                .font(.gluttLargeTitle)
                .foregroundStyle(Theme.Colors.accent)
            Text(label)
                .font(.gluttCaption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }
}
