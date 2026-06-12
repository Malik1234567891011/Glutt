import SwiftData
import SwiftUI

/// Phase 0 placeholder growing up: today's meals, leftovers nudge, and the
/// "what should I cook?" assistant. The full command center lands in Phase 8.
struct TodayView: View {
    @Environment(Router.self) private var router
    @Query private var meals: [PlannedMeal]
    @Query private var leftovers: [Leftover]

    @State private var isAskingWhatToCook = false
    @State private var isShowingSettings = false

    private var todaysMeals: [PlannedMeal] {
        let today = Calendar.current.startOfDay(for: .now)
        return meals
            .filter { $0.date == today }
            .sorted { $0.mealType.sortOrder < $1.mealType.sortOrder }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Text(greeting)
                        .font(.gluttLargeTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    askButton

                    if todaysMeals.isEmpty {
                        EmptyStateView(
                            icon: "sun.max",
                            title: "Nothing planned today",
                            message: "Plan a meal or ask what to cook — your day starts here."
                        )
                    } else {
                        SectionHeader(title: "Today's meals")
                        ForEach(todaysMeals) { meal in
                            MealCard(meal: meal)
                        }
                    }

                    if let leftover = leftovers.first(where: { $0.servingsRemaining > 0 && !$0.isFrozen }) {
                        leftoverReminder(leftover)
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $isAskingWhatToCook) {
                WhatToCookView()
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .onAppear(perform: handlePendingAction)
            .onChange(of: router.pendingAction) { handlePendingAction() }
        }
    }

    private func handlePendingAction() {
        if router.pendingAction == .askWhatToCook {
            router.pendingAction = nil
            isAskingWhatToCook = true
        }
    }

    private var askButton: some View {
        Button {
            isAskingWhatToCook = true
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(Theme.Colors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("What should I cook?")
                        .font(.gluttHeadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Based on your kitchen, your time, and your mood")
                        .font(.gluttCaption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .cardStyle()
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    private func leftoverReminder(_ leftover: Leftover) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "takeoutbag.and.cup.and.straw")
                .font(.title3)
                .foregroundStyle(Theme.Colors.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Leftovers waiting")
                    .font(.gluttHeadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("You still have \(leftover.servingsRemaining.formatted()) servings of \(leftover.title.lowercased()).")
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.warningTint)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}
