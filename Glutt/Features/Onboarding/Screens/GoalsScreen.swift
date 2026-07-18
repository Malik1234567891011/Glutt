import SwiftUI

/// Screen 3 — 6 selectable rows, ≥1 required to continue. Content only; the
/// coordinator owns the fixed (gated) "Continue" footer + chrome.
struct GoalsScreen: View {
    @Bindable var state: OnboardingState

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeadline("Why do you want to cook more at home?", size: 26)
            OnboardingSubhead("Pick anything that sounds like you").padding(.top, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 11) {
                    ForEach(OnboardingState.goalOptions, id: \.self) { goal in
                        row(goal, selected: state.selectedGoals.contains(goal))
                    }
                }
                .padding(2)
            }
            .padding(.top, 20).padding(.bottom, 16)
        }
        .padding(.horizontal, 22)
        .padding(.top, 44)   // design 98 − 54
    }

    private func row(_ goal: String, selected: Bool) -> some View {
        Button {
            Haptics.selection()
            state.toggleGoal(goal)
        } label: {
            HStack(spacing: 14) {
                Text(goal)
                    .font(OnboardingFonts.nunito(15.5, 700))
                    .foregroundStyle(OnboardingTheme.textList)
                Spacer(minLength: 0)
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(selected ? OnboardingTheme.greenDeep : .clear)
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(selected ? OnboardingTheme.greenDeep : OnboardingTheme.warmBlack(0.2), lineWidth: 2)
                    if selected {
                        MS.checkFill.sized(18).foregroundStyle(OnboardingTheme.creamText)
                    }
                }
                .frame(width: 26, height: 26)
            }
            .padding(18)
            .background(selected ? OnboardingTheme.greenTint : OnboardingTheme.surface,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(selected ? OnboardingTheme.greenDeep : OnboardingTheme.warmBlack(0.06), lineWidth: 1.5))
            .shadow(color: OnboardingTheme.warmBlack(0.04), radius: 1.5, y: 1)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: selected)
    }
}
