import SwiftData
import SwiftUI

/// Full-screen step-by-step cooking. Big text, screen stays awake,
/// per-step ingredients and timers, swipe or tap to navigate.
///
/// Runs off the same compiled `CookPlan` as the voice cook rather than the raw
/// recipe steps. It used to read `recipe.sortedSteps` directly, which meant the
/// two cook surfaces told different stories: Polly opened with Tools and Prep
/// and this one dropped the cook straight into "heat the oil" with an unpeeled
/// onion on the board. It also inherited whatever running order the source
/// recipe happened to have, including the one where the chicken goes in the
/// oven for 20 minutes and the potatoes follow it for 30.
struct CookModeView: View {
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    /// Serving scale carried over from the detail screen.
    let scale: Double

    @State private var stepIndex = 0
    @State private var timerManager = TimerManager()
    @State private var isShowingIngredients = false
    @State private var isShowingFinish = false
    @State private var isConfirmingExit = false

    /// Analytics only. `reachedFinish` is what separates a cook from an
    /// abandonment: leaving any other way means they walked off mid-recipe.
    @State private var startedCookingAt = Date()
    @State private var reachedFinish = false

    /// Starts as the deterministic linear plan so the first frame is instant and
    /// offline still works. `ensuringLeadingPrep` runs on that too, so even the
    /// no-AI path opens with Tools and Prep.
    @State private var plan: CookPlan

    private var steps: [CookPlan.PlanStep] { plan.steps }
    private var isLastStep: Bool { stepIndex >= steps.count - 1 }
    private var setupCount: Int { plan.leadingSetupCount }
    /// What the cook counts. Tools and Prep are not "step 1 of 9".
    private var cookStepTotal: Int { max(1, steps.count - setupCount) }

    init(recipe: Recipe, scale: Double = 1) {
        self.recipe = recipe
        self.scale = scale
        _plan = State(initialValue: CookPlan.linear(from: recipe, scale: scale))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            progressBar

            TabView(selection: $stepIndex) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    stepPage(step, index: index)
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
        // Usually instant: the detail screen warms this cache while the cook is
        // still reading. Swapped in only while they are still on the first
        // page, because re-ordering the steps under someone who is already
        // cooking is worse than letting them finish on the linear plan.
        .task {
            let compiled = await CookPlanCompiler.compile(recipe: recipe, scale: scale)
            guard stepIndex == 0, !compiled.isFallback else { return }
            plan = compiled
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            startedCookingAt = .now
            Analytics.capture(.cookStarted, [
                "with_polly": false,
                "steps_total": steps.count,
            ])
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            timerManager.cancelAll()
            Analytics.capture(.cookFinished, [
                "with_polly": false,
                "duration_s": Int(Date.now.timeIntervalSince(startedCookingAt).rounded()),
                "ended_early": !reachedFinish,
                "steps_done": reachedFinish ? steps.count : stepIndex,
                "steps_total": steps.count,
            ])
        }
        // Catches both ways in: the last-step button and "Finish & log it" in
        // the exit dialog. Sheets do not disappear their presenter, so this
        // stays true through the finish sheet and into `onDisappear`.
        .onChange(of: isShowingFinish) { _, showing in
            if showing { reachedFinish = true }
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
                    .frame(width: 17, height: 17)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(width: 40, height: 40)
                    .overlay(Circle().stroke(Theme.Colors.border, lineWidth: 1))
                    .clipShape(Circle())
                    // The drawn circle stays 40; only the tappable area grows.
                    // This is the screen used with wet hands, and 40 is under
                    // the 44 minimum on the two controls that leave it.
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Stop cooking")
            Spacer()
            VStack(spacing: 1) {
                Text(recipe.title)
                    .font(BrandFont.nunito(13, 800, relativeTo: .caption1, maxSize: 20))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Text(stepCounterLabel)
                    .font(BrandFont.nunito(11.5, 700, relativeTo: .caption2, maxSize: 18))
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
                    .frame(width: 40, height: 40)
                    .overlay(Circle().stroke(Theme.Colors.border, lineWidth: 1))
                    .clipShape(Circle())
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("All ingredients")
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

    private func stepPage(_ step: CookPlan.PlanStep, index: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    stepBadge(step, index: index)
                    Spacer()
                }

                Text(CookModeView.silentInstruction(step.instruction))
                    // Capped at 40. The instruction is the thing somebody
                    // reads from across a counter, so it should grow further
                    // than anything else here, but past 40 it starts pushing
                    // the supporting blocks off the screen entirely.
                    .font(BrandFont.bricolage(27, 600, relativeTo: .title2, maxSize: 40))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                // Directly under the instruction, above the supporting blocks.
                //
                // It used to sit between LOOK FOR and IF IT GOES WRONG, which
                // put a solid amber button immediately above an amber tinted
                // block: two ambers touching, the louder one not the warning.
                // It also split the two callouts. The timer is the action the
                // instruction implies, so it reads in that order and the two
                // ambers end up separated by the olive block between them.
                if let duration = step.offerableTimerSeconds {
                    timerChip(for: step, index: index, duration: duration)
                }

                if let look = step.visualCheck, !look.isEmpty {
                    calloutRow("LOOK FOR", look, tint: Theme.Colors.accent)
                }

                if let recovery = step.recovery, !recovery.isEmpty {
                    calloutRow("IF IT GOES WRONG", recovery,
                               tint: Theme.Colors.warning, opacity: 0.18)
                }

                let used = ingredients(for: step)
                if !used.isEmpty {
                    supportBlock("FOR THIS STEP",
                                 tint: Theme.Colors.textSecondary,
                                 surface: Theme.Colors.textSecondary) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(used) { ingredient in
                                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                                    Circle()
                                        .fill(Theme.Colors.textSecondary.opacity(0.5))
                                        .frame(width: 5, height: 5)
                                    Text(ingredientLabel(ingredient))
                                        .font(BrandFont.nunito(15, 600, relativeTo: .subheadline, maxSize: 26))
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            }
            .padding(Theme.Spacing.lg)
        }
    }

    private func timerChip(for step: CookPlan.PlanStep, index: Int, duration: Int) -> some View {
        Button {
            Haptics.selection()
            timerManager.start(
                label: "\(badgeText(step, index: index)): \(String(step.title.prefix(40)))",
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
            .padding(.vertical, 15)
            .background(Theme.Colors.warning)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start a \(TimerManager.format(seconds: duration)) timer")
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
                            Haptics.impact(.light)
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
                    Haptics.celebrate()
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

    // MARK: - Step labelling

    /// Tools and Prep are setup, not "step 1". Mirrors the voice cook's
    /// numbering (`PollySessionSubviews.stepPage`) so the same dish reads the
    /// same way whichever way the cook runs it.
    private func badgeText(_ step: CookPlan.PlanStep, index: Int) -> String {
        // The badge under this already names the step "Tools" or "Prep". The
        // header's job is where you are, not what it is called, so repeating
        // the word verbatim added nothing. "Setup" says the thing the badge
        // does not: that this comes before the counted steps.
        if CookPlan.isSetupStep(step) { return "Setup" }
        return "\(max(1, index + 1 - setupCount))"
    }

    private var stepCounterLabel: String {
        guard steps.indices.contains(stepIndex) else { return "" }
        let step = steps[stepIndex]
        if step.id == CookPlan.toolsStepID { return "Tools" }
        if step.id == CookPlan.prepStepID { return "Prep" }
        return "Step \(max(1, stepIndex + 1 - setupCount)) of \(cookStepTotal)"
    }

    @ViewBuilder
    private func stepBadge(_ step: CookPlan.PlanStep, index: Int) -> some View {
        let text = badgeText(step, index: index)
        let isSetup = CookPlan.isSetupStep(step)
        Text(text)
            .font(.gluttHeadline).foregroundStyle(.white)
            .padding(.horizontal, isSetup ? 14 : 0)
            .frame(minWidth: 32, minHeight: 32)
            .background(
                Capsule().fill(isSetup ? Theme.Colors.muted : Theme.Colors.accent)
            )
    }

    /// The setup steps are written to be spoken by Polly and end by asking the
    /// cook to say when they are done ("Tell me when they're on the counter").
    /// On this screen there is nobody to tell, so that sentence reads as a bug.
    /// Stripped here rather than in `CookPlan`, because the voice cook wants it
    /// and the plan is shared.
    static func silentInstruction(_ text: String) -> String {
        let sentences = text.split(separator: ".", omittingEmptySubsequences: false)
        let kept = sentences.filter { sentence in
            let lowered = sentence.trimmingCharacters(in: .whitespaces).lowercased()
            return !lowered.hasPrefix("tell me when") && !lowered.hasPrefix("let me know")
        }
        let rebuilt = kept.joined(separator: ".").trimmingCharacters(in: .whitespaces)
        // Never hand back nothing: if the whole instruction was the aside, the
        // original is still better than a blank step.
        return rebuilt.isEmpty ? text : rebuilt
    }

    /// The one construction every supporting block on this screen uses.
    ///
    /// LOOK FOR, IF IT GOES WRONG and FOR THIS STEP are peers: three things the
    /// cook may want while doing the same step. They used to be built three
    /// different ways, and the difference was not carrying meaning. Two were a
    /// colour tinted 10% over the cream; the third was an opaque near-white
    /// card, which read as a different class of object sitting on top of the
    /// page rather than a sibling of the two above it.
    ///
    /// Now they share padding, radius, label style, and the gap between label
    /// and body, and differ only in tint strength, which is the one axis
    /// carrying actual meaning:
    ///
    /// - **LOOK FOR** accent at 10%, an olive wash. Calm: this is what success
    ///   looks like, and it is not urgent.
    /// - **FOR THIS STEP** a warm neutral at 10%. The quietest, because it is
    ///   reference rather than instruction.
    /// - **IF IT GOES WRONG** amber at 18%, and the only one that reads as a
    ///   raised voice. It is the block a cook needs when something is actually
    ///   burning, so it is allowed to be found faster than its peers.
    @ViewBuilder
    private func supportBlock(
        _ label: String,
        tint: Color,
        surface: Color,
        opacity: Double = 0.10,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(BrandFont.nunito(12, 800, relativeTo: .caption2, maxSize: 19))
                .textCase(.uppercase)
                .foregroundStyle(tint)
            content()
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface.opacity(opacity))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.photo, style: .continuous))
    }

    private func calloutRow(
        _ label: String,
        _ text: String,
        tint: Color,
        opacity: Double = 0.10
    ) -> some View {
        supportBlock(label, tint: tint, surface: tint, opacity: opacity) {
            Text(text)
                .font(BrandFont.nunito(15, 600, relativeTo: .subheadline, maxSize: 26))
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What this step touches. The compiler names them (`ingredientNames`), and
    /// only when it gives us nothing do we fall back to matching words in the
    /// text, which is what the raw-step version always did.
    private func ingredients(for step: CookPlan.PlanStep) -> [RecipeIngredient] {
        let all = recipe.ingredients
        if !step.ingredientNames.isEmpty {
            let wanted = Set(step.ingredientNames.map { $0.lowercased() })
            let named = all.filter { ingredient in
                wanted.contains(ingredient.name.lowercased())
                    || wanted.contains(ingredient.canonicalName.lowercased())
            }
            if !named.isEmpty { return named.sorted { $0.sortIndex < $1.sortIndex } }
        }
        return CookModeView.ingredientsMentioned(in: step.instruction, from: all)
    }

    /// Name-in-text matching, shared with the old raw-step path.
    static func ingredientsMentioned(
        in text: String, from ingredients: [RecipeIngredient]
    ) -> [RecipeIngredient] {
        let lowered = text.lowercased()
        return ingredients
            .filter { ingredient in
                let words = ingredient.canonicalName.split(separator: " ").map(String.init)
                return words.contains { $0.count > 2 && lowered.contains($0) }
            }
            .sorted { $0.sortIndex < $1.sortIndex }
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
    ///
    /// Still used by the linear plan builder and the clip matcher. Cook mode now
    /// prefers the compiler's `ingredientNames` and only falls back to this.
    func ingredientsUsed(from ingredients: [RecipeIngredient]) -> [RecipeIngredient] {
        CookModeView.ingredientsMentioned(in: text, from: ingredients)
    }
}
