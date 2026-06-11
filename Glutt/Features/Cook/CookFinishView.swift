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
    @State private var servingsEaten: Double = 1
    @State private var saveLeftovers = true
    @State private var rating = 0
    @State private var worthTheEffort: Bool?
    @State private var wouldMakeAgain: Bool?
    @State private var note = ""

    init(recipe: Recipe, scale: Double, onComplete: @escaping () -> Void) {
        self.recipe = recipe
        self.scale = scale
        self.onComplete = onComplete
        _servingsMade = State(initialValue: Double(recipe.servings) * scale)
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

                    Button("Save & finish") { save() }
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
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            stepperRow(
                title: "Servings made",
                value: $servingsMade,
                range: 0.5...24
            )
            Divider().overlay(Theme.Colors.border)
            stepperRow(
                title: "How much did you eat?",
                value: $servingsEaten,
                range: 0...servingsMade
            )
        }
        .cardStyle()
    }

    private func stepperRow(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title)
                .font(.gluttBody)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Stepper(
                value: value,
                in: range,
                step: 0.5
            ) {
                Text(value.wrappedValue.formatted())
                    .font(.gluttHeadline)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(minWidth: 36)
            }
            .fixedSize()
        }
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
        }
        .cardStyle()
    }

    private var feedbackCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        rating = rating == star ? 0 : star
                    } label: {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundStyle(Theme.Colors.warning)
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
                answer.wrappedValue = answer.wrappedValue == true ? nil : true
            } label: {
                Image(systemName: answer.wrappedValue == true ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .foregroundStyle(Theme.Colors.accent)
            }
            .buttonStyle(.plain)
            Button {
                answer.wrappedValue = answer.wrappedValue == false ? nil : false
            } label: {
                Image(systemName: answer.wrappedValue == false ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    .foregroundStyle(Theme.Colors.tomato)
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
