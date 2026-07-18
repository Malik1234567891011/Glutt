import SwiftData
import SwiftUI

/// End-of-cooking feedback: rate the dish and leave a quick note.
/// Records a `CookSession` (cook history) — no intake/leftover tracking.
struct CookFinishView: View {
    @Environment(\.modelContext) private var context

    let recipe: Recipe
    let scale: Double
    let onComplete: () -> Void

    @State private var rating = 0
    @State private var worthTheEffort: Bool?
    @State private var wouldMakeAgain: Bool?
    @State private var note = ""

    init(recipe: Recipe, scale: Double, onComplete: @escaping () -> Void) {
        self.recipe = recipe
        self.scale = scale
        self.onComplete = onComplete
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header
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
        let servingsMade = max(1, Int((Double(recipe.servings) * scale).rounded()))
        let session = CookSession(servingsMade: servingsMade, recipe: recipe)
        session.rating = rating > 0 ? rating : nil
        session.notes = note.isEmpty ? nil : note
        session.worthTheEffort = worthTheEffort
        session.wouldMakeAgain = wouldMakeAgain
        context.insert(session)

        // First star rating becomes the recipe's rating if it has none.
        if recipe.rating == nil, rating > 0 {
            recipe.rating = rating
        }

        onComplete()
    }
}
