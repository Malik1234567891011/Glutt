import SwiftData
import SwiftUI

/// End-of-cooking flow: this is where cooking creates data.
/// Servings made/eaten -> FoodLog, remainder -> Leftover, quick feedback -> CookSession.
struct CookFinishView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var plannedMeals: [PlannedMeal]

    let recipe: Recipe
    let scale: Double
    let onComplete: () -> Void

    @State private var servingsMade: Double
    @State private var eatenFraction: Double
    @State private var saveLeftovers = true
    @State private var rating = 0
    @State private var worthTheEffort: Bool?
    @State private var wouldMakeAgain: Bool?
    @State private var note = ""

    /// "How much of it did you eat?" — fractions are how people actually think
    /// about a pot of food, and accurate leftovers depend on this answer.
    private static let portionOptions: [(label: String, fraction: Double)] = [
        ("None", 0), ("¼", 0.25), ("½", 0.5), ("¾", 0.75), ("All", 1),
    ]

    init(recipe: Recipe, scale: Double, onComplete: @escaping () -> Void) {
        self.recipe = recipe
        self.scale = scale
        self.onComplete = onComplete
        let made = Double(recipe.servings) * scale
        _servingsMade = State(initialValue: made)
        // Start near "one person ate one serving", snapped to a portion chip.
        let oneServing = made > 0 ? 1 / made : 1
        let snapped = Self.portionOptions.min { abs($0.fraction - oneServing) < abs($1.fraction - oneServing) }!
        _eatenFraction = State(initialValue: snapped.fraction)
    }

    private var servingsEaten: Double {
        (servingsMade * eatenFraction * 2).rounded() / 2
    }

    private var leftoverServings: Double {
        max(0, servingsMade - servingsEaten)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header
                    servingsCard
                    if leftoverServings > 0 {
                        leftoversCard
                    }
                    feedbackCard
                    noteCard

                    Button("Save & finish") {
                        Haptics.notify(.success)
                        save()
                    }
                    .buttonStyle(.gluttPrimary)
                    Button("Skip — just close") {
                        onComplete()
                    }
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Nice cooking!")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            RecipeImageView(recipe: recipe)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.title)
                    .font(.gluttHeadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Cooked \(Date.now.formatted(.dateTime.month().day().hour().minute()))")
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
        }
    }

    private var servingsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Servings made")
                    .font(.gluttBody)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Stepper(value: $servingsMade, in: 0.5...24, step: 0.5) {
                    Text(servingsMade.formatted())
                        .font(.gluttHeadline)
                        .foregroundStyle(Theme.Colors.accent)
                        .frame(minWidth: 36)
                }
                .fixedSize()
                .onChange(of: servingsMade) { _, _ in Haptics.impact(.light) }
            }

            Divider().overlay(Theme.Colors.border)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("How much of it did you eat?")
                    .font(.gluttBody)
                    .foregroundStyle(Theme.Colors.textPrimary)
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(Self.portionOptions, id: \.fraction) { option in
                        Button {
                            eatenFraction = option.fraction
                        } label: {
                            Text(option.label)
                                .font(.gluttHeadline)
                                .foregroundStyle(eatenFraction == option.fraction ? .white : Theme.Colors.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Theme.Spacing.sm)
                                .background(
                                    eatenFraction == option.fraction
                                        ? Theme.Colors.accent
                                        : Theme.Colors.accent.opacity(0.08)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if eatenFraction > 0 {
                    Text("≈ \(servingsEaten.formatted()) of \(servingsMade.formatted()) servings")
                        .font(.gluttCaption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .cardStyle()
    }

    private var leftoversCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Save \(leftoverServings.formatted()) servings as leftovers?")
                    .font(.gluttHeadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Glutt will remind you before they go bad.")
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            Toggle("", isOn: $saveLeftovers)
                .labelsHidden()
                .tint(Theme.Colors.accent)
                .hapticOnChange(of: saveLeftovers)
        }
        .cardStyle()
    }

    private var feedbackCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        Haptics.impact(.light)
                        rating = rating == star ? 0 : star
                    } label: {
                        if star <= rating {
                            Ph.star.fill
                                .resizable().scaledToFit()
                                .frame(width: 28, height: 28)
                                .foregroundStyle(Theme.Colors.warning)
                        } else {
                            Ph.star.regular
                                .resizable().scaledToFit()
                                .frame(width: 28, height: 28)
                                .foregroundStyle(Theme.Colors.warning)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            quickQuestion("Worth the effort?", answer: $worthTheEffort)
            quickQuestion("Make it again?", answer: $wouldMakeAgain)
        }
        .cardStyle()
    }

    private func quickQuestion(_ question: String, answer: Binding<Bool?>) -> some View {
        HStack {
            Text(question)
                .font(.gluttBody)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Button {
                Haptics.impact(.light)
                answer.wrappedValue = answer.wrappedValue == true ? nil : true
            } label: {
                if answer.wrappedValue == true {
                    Ph.thumbsUp.fill
                        .resizable().scaledToFit()
                        .frame(width: 22, height: 22)
                        .foregroundStyle(Theme.Colors.accent)
                } else {
                    Ph.thumbsUp.regular
                        .resizable().scaledToFit()
                        .frame(width: 22, height: 22)
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            .buttonStyle(.plain)
            Button {
                Haptics.impact(.light)
                answer.wrappedValue = answer.wrappedValue == false ? nil : false
            } label: {
                if answer.wrappedValue == false {
                    Ph.thumbsDown.fill
                        .resizable().scaledToFit()
                        .frame(width: 22, height: 22)
                        .foregroundStyle(Theme.Colors.tomato)
                } else {
                    Ph.thumbsDown.regular
                        .resizable().scaledToFit()
                        .frame(width: 22, height: 22)
                        .foregroundStyle(Theme.Colors.tomato)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var noteCard: some View {
        TextField("Quick note: add more lemon, too salty…", text: $note, axis: .vertical)
            .font(.gluttBody)
            .lineLimit(2...5)
            .cardStyle()
    }

    // MARK: - Save

    private func save() {
        let session = CookSession(
            servingsMade: Int(servingsMade.rounded()),
            servingsEaten: servingsEaten,
            recipe: recipe
        )
        session.rating = rating > 0 ? rating : nil
        session.notes = note.isEmpty ? nil : note
        session.worthTheEffort = worthTheEffort
        session.wouldMakeAgain = wouldMakeAgain
        context.insert(session)

        // Eating something? Log it.
        if servingsEaten > 0 {
            let log = FoodLog(
                title: recipe.title,
                source: .cookedMeal,
                calories: recipe.calories.map { Int(Double($0) * servingsEaten) },
                proteinGrams: recipe.proteinGrams.map { Int(Double($0) * servingsEaten) }
            )
            context.insert(log)
        }

        // Anything left? Track it.
        if saveLeftovers, leftoverServings > 0 {
            let leftover = Leftover(
                title: recipe.title,
                servingsRemaining: leftoverServings,
                sourceRecipe: recipe
            )
            leftover.caloriesPerServing = recipe.calories
            leftover.proteinPerServing = recipe.proteinGrams
            context.insert(leftover)
        }

        // Close the planning loop: mark today's matching planned meal.
        let today = Calendar.current.startOfDay(for: .now)
        if let planned = plannedMeals.first(where: { $0.date == today && $0.recipe === recipe }) {
            planned.status = servingsEaten > 0 ? .eaten : .cooked
        }

        // First star rating becomes the recipe's rating if it has none.
        if recipe.rating == nil, rating > 0 {
            recipe.rating = rating
        }

        onComplete()
    }
}
