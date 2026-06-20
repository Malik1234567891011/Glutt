import SwiftData
import SwiftUI

/// Full-screen step-by-step cooking. Big text, screen stays awake,
/// per-step ingredients and timers, swipe or tap to navigate.
struct CookModeView: View {
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    /// Serving scale carried over from the detail screen.
    var scale: Double = 1

    @State private var stepIndex = 0
    @State private var timerManager = TimerManager()
    @State private var isShowingIngredients = false
    @State private var isShowingFinish = false
    @State private var isConfirmingExit = false

    private var steps: [RecipeStep] { recipe.sortedSteps }
    private var isLastStep: Bool { stepIndex >= steps.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            progressBar

            TabView(selection: $stepIndex) {
                ForEach(Array(steps.enumerated()), id: \.element.persistentModelID) { index, step in
                    stepPage(step)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.2), value: stepIndex)

            if !timerManager.timers.isEmpty {
                activeTimersBar
            }

            bottomBar
        }
        .background(Theme.Colors.background)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            timerManager.cancelAll()
        }
        .sheet(isPresented: $isShowingIngredients) {
            ingredientsSheet
        }
        .sheet(isPresented: $isShowingFinish) {
            CookFinishView(recipe: recipe, scale: scale) {
                dismiss()
            }
            .interactiveDismissDisabled()
        }
        .confirmationDialog("Stop cooking?", isPresented: $isConfirmingExit, titleVisibility: .visible) {
            Button("Keep cooking", role: .cancel) {}
            Button("Exit without saving", role: .destructive) { dismiss() }
            Button("Finish & log it") { isShowingFinish = true }
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Button {
                Haptics.impact(.light)
                isConfirmingExit = true
            } label: {
                Ph.x.regular
                    .resizable().scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(10)
                    .background(Theme.Colors.card)
                    .clipShape(Circle())
            }
            Spacer()
            VStack(spacing: 0) {
                Text(recipe.title)
                    .font(.gluttCaption.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Text("Step \(stepIndex + 1) of \(steps.count)")
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            Button {
                isShowingIngredients = true
            } label: {
                Ph.listBullets.regular
                    .resizable().scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(10)
                    .background(Theme.Colors.card)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.border)
                Capsule()
                    .fill(Theme.Colors.accent)
                    .frame(width: proxy.size.width * Double(stepIndex + 1) / Double(max(steps.count, 1)))
                    .animation(.easeOut(duration: 0.25), value: stepIndex)
            }
        }
        .frame(height: 5)
        .padding(.horizontal, Theme.Spacing.md)
    }

    // MARK: - Step page

    private func stepPage(_ step: RecipeStep) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Text("\(step.index + 1)")
                        .font(.gluttHeadline).foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Theme.Colors.accent).clipShape(Circle())
                    Spacer()
                }

                Text(step.text)
                    .font(.gluttCookStep)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let duration = step.durationSeconds {
                    timerChip(for: step, duration: duration)
                }

                let used = step.ingredientsUsed(from: recipe.ingredients)
                if !used.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("FOR THIS STEP")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        ForEach(used) { ingredient in
                            HStack {
                                Circle()
                                    .fill(Theme.Colors.accent.opacity(0.5))
                                    .frame(width: 6, height: 6)
                                Text(ingredientLabel(ingredient))
                                    .font(.gluttBody)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                            }
                        }
                    }
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.card)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                }
            }
            .padding(Theme.Spacing.lg)
        }
    }

    private func timerChip(for step: RecipeStep, duration: Int) -> some View {
        Button {
            Haptics.selection()
            timerManager.start(
                label: "Step \(step.index + 1): \(String(step.text.prefix(40)))",
                seconds: duration
            )
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Ph.timer.regular
                    .resizable().scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(.white)
                Text("Start \(TimerManager.format(seconds: duration)) timer")
                    .font(.gluttHeadline)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 12)
            .background(Theme.Colors.warning)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Timers bar

    private var activeTimersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(timerManager.timers) { timer in
                    let remaining = timer.remainingSeconds(at: timerManager.now)
                    HStack(spacing: 6) {
                        if remaining == 0 {
                            Ph.bellRinging.fill
                                .resizable().scaledToFit()
                                .frame(width: 16, height: 16)
                                .foregroundStyle(.white)
                                .onAppear { Haptics.notify(.success) }
                        } else {
                            Ph.timer.regular
                                .resizable().scaledToFit()
                                .frame(width: 16, height: 16)
                                .foregroundStyle(.white)
                        }
                        Text(remaining == 0 ? "Done!" : TimerManager.format(seconds: remaining))
                            .monospacedDigit()
                        Button {
                            timerManager.cancel(timer)
                        } label: {
                            Ph.xCircle.fill
                                .resizable().scaledToFit()
                                .frame(width: 16, height: 16)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .font(.gluttCaption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(remaining == 0 ? Theme.Colors.tomato : Theme.Colors.accent)
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: Theme.Spacing.md) {
            if stepIndex > 0 {
                Button {
                    Haptics.impact(.light)
                    stepIndex -= 1
                } label: {
                    HStack(spacing: 4) {
                        Ph.caretLeft.regular
                            .resizable().scaledToFit()
                            .frame(width: 14, height: 14)
                        Text("Back")
                    }
                }
                .buttonStyle(.gluttSecondary)
                .frame(width: 110)
            }

            if isLastStep {
                Button("Finish cooking") {
                    Haptics.impact(.medium)
                    isShowingFinish = true
                }
                .buttonStyle(.gluttPrimary)
            } else {
                Button {
                    Haptics.impact(.medium)
                    stepIndex += 1
                } label: {
                    HStack(spacing: 4) {
                        Text("Next step")
                        Ph.caretRight.regular
                            .resizable().scaledToFit()
                            .frame(width: 14, height: 14)
                    }
                }
                .buttonStyle(.gluttPrimary)
            }
        }
        .padding(Theme.Spacing.md)
    }

    // MARK: - Ingredients sheet

    private var ingredientsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    let sorted = recipe.ingredients.sorted { $0.sortIndex < $1.sortIndex }
                    ForEach(sorted) { ingredient in
                        HStack {
                            Text(ingredient.name)
                                .font(.gluttBody)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Spacer()
                            if let display = UnitConverter.display(
                                quantity: ingredient.quantity, unit: ingredient.unit, scale: scale
                            ) {
                                Text(display)
                                    .font(.gluttBody.weight(.medium))
                                    .foregroundStyle(Theme.Colors.accent)
                            }
                        }
                        .padding(.vertical, Theme.Spacing.sm)
                        .padding(.horizontal, Theme.Spacing.md)
                        if ingredient !== sorted.last {
                            Divider().overlay(Theme.Colors.border)
                        }
                    }
                }
            }
            .background(Theme.Colors.background)
            .navigationTitle("Ingredients")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private func ingredientLabel(_ ingredient: RecipeIngredient) -> String {
        if let display = UnitConverter.display(quantity: ingredient.quantity, unit: ingredient.unit, scale: scale) {
            return "\(display) \(ingredient.name)"
        }
        return ingredient.name
    }
}

extension RecipeStep {
    /// Ingredients referenced by this step, matched by name appearing in the step text.
    /// Heuristic on purpose — no model change needed, and import sources never link steps to ingredients.
    func ingredientsUsed(from ingredients: [RecipeIngredient]) -> [RecipeIngredient] {
        let lowered = text.lowercased()
        return ingredients
            .filter { ingredient in
                let words = ingredient.canonicalName.split(separator: " ").map(String.init)
                return words.contains { $0.count > 2 && lowered.contains($0) }
            }
            .sorted { $0.sortIndex < $1.sortIndex }
    }
}
