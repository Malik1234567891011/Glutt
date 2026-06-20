import SwiftUI
import PhosphorSwift

/// Single-select nutrition mode.
struct NutritionScreen: View {
    @Bindable var state: OnboardingState

    private struct ModeRow {
        let mode: NutritionMode
        let icon: Image
        let detail: String
    }

    private let rows: [ModeRow] = [
        .init(
            mode: .cookingOnly,
            icon: Ph.cookingPot.regular,
            detail: "No calories, no macros, anywhere. Just good food."
        ),
        .init(
            mode: .lightTracking,
            icon: Ph.chartBar.regular,
            detail: "Gentle estimates on recipes and a daily summary."
        ),
        .init(
            mode: .gymMode,
            icon: Ph.barbell.regular,
            detail: "Calorie & protein goals, charts, and per-serving macros."
        ),
    ]

    var body: some View {
        OnboardingScaffold(
            title: "Want to track nutrition?",
            subtitle: "Totally optional. You can change this anytime in Settings."
        ) {
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(rows, id: \.mode) { row in
                    OptionRow(
                        leadingIcon: row.icon
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                            .foregroundStyle(Theme.Colors.accent),
                        title: row.mode.label,
                        subtitle: row.detail,
                        isSelected: state.nutritionMode == row.mode
                    ) {
                        Haptics.selection()
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
