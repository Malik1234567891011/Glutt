import Charts
import PhosphorSwift
import SwiftData
import SwiftUI

/// Progress: cooking wins by default, nutrition only when the user asks
/// for it (gym mode / light tracking). Calm copy, ranges over false
/// precision, zero guilt mechanics.
struct ProgressTabView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CookSession.date, order: .reverse) private var sessions: [CookSession]
    @Query(sort: \FoodLog.timestamp, order: .reverse) private var logs: [FoodLog]

    @State private var isShowingSettings = false

    private var prefs: UserPrefs {
        UserPrefs.current(in: context)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    cookingStatsGrid

                    if prefs.nutritionMode.showsNutrition {
                        nutritionSection
                    } else {
                        gymModeTeaser
                    }

                    if !favoriteMeals.isEmpty {
                        favoritesSection
                    }

                    weeklyRecap
                }
                .padding(Theme.Spacing.md)
            }
            .contentMargins(.bottom, 56, for: .scrollContent)
            .background(Theme.Colors.background)
            .navigationTitle("Progress")
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
        }
    }

    // MARK: - Cooking stats (always on)

    private var cookingStatsGrid: some View {
        let thisWeek = ProgressStats.sessionsThisWeek(sessions)
        let streak = ProgressStats.cookingStreak(sessions: sessions)
        let tried = ProgressStats.recipesTried(sessions: sessions)
        let leftoversUsed = ProgressStats.leftoversUsed(logs: logs)
        let eatingOut = ProgressStats.eatingOutCount(logs: logs)

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.sm) {
            statCard(value: "\(thisWeek.count)", label: "meals cooked this week") {
                Ph.cookingPot.fill
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(Theme.Colors.accent)
            }
            statCard(
                value: streak > 0 ? "\(streak)" : "—",
                label: streak == 1 ? "day cooking streak" : "days cooking streak"
            ) {
                Ph.flame.fill
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(Theme.Colors.tomato)
            }
            statCard(value: "\(tried.total)", label: tried.newThisMonth > 0 ? "recipes tried (\(tried.newThisMonth) new this month)" : "recipes tried") {
                Ph.book.fill
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(Theme.Colors.accent)
            }
            statCard(value: "\(leftoversUsed)", label: "leftovers eaten this week") {
                Ph.bag.fill
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(Theme.Colors.accent)
            }
            if eatingOut > 0 {
                statCard(value: "\(eatingOut)", label: "restaurant meals this week") {
                    Ph.storefront.fill
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
        }
    }

    private func statCard<Icon: View>(value: String, label: String, @ViewBuilder icon: () -> Icon) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                icon()
                Spacer()
            }
            Text(value)
                .font(.gluttTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Nutrition (gym / light tracking)

    private var nutritionSection: some View {
        let daily = ProgressStats.dailyTotals(logs: logs)

        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Last 7 days")

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                chart(
                    title: "Calories",
                    data: daily.map { (day: $0.day, value: $0.calories) },
                    goal: prefs.dailyCalorieGoal
                )
                chart(
                    title: "Protein (g)",
                    data: daily.map { (day: $0.day, value: $0.protein) },
                    goal: prefs.dailyProteinGoal
                )
                Text("Days with no logs just mean you didn't track — not that you didn't eat. All good.")
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .cardStyle()
        }
    }

    private func chart(title: String, data: [(day: Date, value: Int)], goal: Int?) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(.gluttCaption.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Chart {
                ForEach(data, id: \.day) { point in
                    BarMark(
                        x: .value("Day", point.day, unit: .day),
                        y: .value(title, point.value)
                    )
                    .foregroundStyle(Theme.Colors.accent.opacity(0.75))
                    .cornerRadius(3)
                }
                if let goal {
                    RuleMark(y: .value("Goal", goal))
                        .foregroundStyle(Theme.Colors.warning)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4]))
                }
            }
            .frame(height: 110)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            }
        }
    }

    private var gymModeTeaser: some View {
        Button {
            Haptics.impact(.light)
            isShowingSettings = true
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                Ph.barbell.regular
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .foregroundStyle(Theme.Colors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tracking calories or protein?")
                        .font(.gluttHeadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Turn on light tracking or gym mode in Settings — charts and goals appear here.")
                        .font(.gluttCaption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                Ph.caretRight.regular
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.cardLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.cardLarge, style: .continuous)
                .strokeBorder(Theme.Colors.border.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: Theme.Colors.textPrimary.opacity(0.07), radius: 10, x: 0, y: 3)
    }

    // MARK: - Favorites & recap

    private var favoriteMeals: [(recipe: Recipe, cookCount: Int)] {
        ProgressStats.favoriteRecipes(sessions: sessions)
    }

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Your favorites")
            ForEach(favoriteMeals, id: \.recipe.persistentModelID) { favorite in
                HStack(spacing: Theme.Spacing.md) {
                    RecipeImageView(recipe: favorite.recipe)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(favorite.recipe.title)
                            .font(.gluttHeadline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(1)
                        Text("^[cooked \(favorite.cookCount) time](inflect: true)")
                            .font(.gluttCaption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    if let rating = favorite.recipe.rating {
                        StatPill.rating("\(rating)")
                    }
                }
                .cardStyle()
            }
        }
    }

    private var weeklyRecap: some View {
        let thisWeek = ProgressStats.sessionsThisWeek(sessions)
        let leftoversUsed = ProgressStats.leftoversUsed(logs: logs)

        let line: String
        if thisWeek.isEmpty {
            line = "Quiet kitchen this week. The plan tab makes restarting easy — even one meal counts."
        } else if leftoversUsed > 0 {
            line = "You cooked \(thisWeek.count) meals and rescued \(leftoversUsed) servings of leftovers. That's real money and real food saved."
        } else {
            line = "You cooked \(thisWeek.count) meals this week. Keep them coming."
        }

        return HStack(spacing: Theme.Spacing.md) {
            Ph.sparkle.fill
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 26)
                .foregroundStyle(Theme.Colors.accent)
            Text(line)
                .font(.gluttBody)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.successTint)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.cardLarge, style: .continuous))
    }
}
