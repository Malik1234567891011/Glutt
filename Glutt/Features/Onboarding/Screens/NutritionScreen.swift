import SwiftUI

/// Single-select nutrition mode.
struct NutritionScreen: View {
    @Bindable var state: OnboardingState

    private struct ModeRow {
        let mode: NutritionMode
        let icon: String
        let detail: String
    }

    private let rows: [ModeRow] = [
        .init(mode: .cookingOnly, icon: "frying.pan", detail: "No calories, no macros, anywhere. Just good food."),
        .init(mode: .lightTracking, icon: "chart.bar", detail: "Gentle estimates on recipes and a daily summary."),
        .init(mode: .gymMode, icon: "dumbbell", detail: "Calorie & protein goals, charts, and per-serving macros."),
    ]

    var body: some View {
        OnboardingScaffold(
            title: "Want to track nutrition?",
            subtitle: "Totally optional. You can change this anytime in Settings."
        ) {
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(rows, id: \.mode) { row in
                    OptionRow(
                        systemImage: row.icon,
                        title: row.mode.label,
                        subtitle: row.detail,
                        isSelected: state.nutritionMode == row.mode
                    ) {
                        state.nutritionMode = row.mode
                    }
                }
            }
        }
    }
}

#Preview {
    NutritionScreen(state: OnboardingState())
        .background(Theme.Colors.background)
}
