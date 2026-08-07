import SwiftData
import SwiftUI

/// "Your weeks": the planned sets, kept together on the Recipes home.
///
/// A week is not five recipes that happen to have arrived at once, it is one
/// shop. Letting the dinners loose into the library lost that immediately: they
/// scattered down the feed among imports, out of order, each one a tall card
/// with no photo, and nothing left to say they belonged to each other or to the
/// list still sitting in Groceries. The rail is the set staying a set.
///
/// Modelled on `ChefRail` and `RestaurantRail`, which already establish the
/// horizontal-rail-under-a-section-label pattern on this screen. Each card
/// pushes the plan's `RecipeCollection`, so the destination is the collection
/// screen the app already has rather than a second one built for this.
struct WeekPlanRail: View {
    @Query(sort: \MealPlan.createdAt, order: .reverse) private var plans: [MealPlan]

    var body: some View {
        if !plans.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel(text: "Your weeks")
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 10)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(plans) { plan in
                            if let collection = plan.collection {
                                NavigationLink(value: collection) { card(plan) }
                                    .buttonStyle(.plain)
                                    .hapticTap()
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
                }
            }
        }
    }

    private func card(_ plan: MealPlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            cover(plan)
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.name)
                    .font(BrandFont.bricolage(16, 700))
                    .foregroundStyle(Theme.Colors.heading)
                    .lineLimit(1)
                Text(subtitle(plan))
                    .font(BrandFont.nunito(12, 700))
                    .foregroundStyle(Theme.Colors.muted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .frame(width: 188, alignment: .leading)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.cardLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.cardLarge, style: .continuous)
                .strokeBorder(Theme.Colors.border.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: Theme.Colors.textPrimary.opacity(0.07), radius: 10, y: 3)
    }

    /// A drawn cover rather than a photograph.
    ///
    /// Every food image in the bundle is a specific dish, and putting the
    /// birria tacos on top of a week that contains no tacos is worse than
    /// having no picture: it is a small lie the cook will notice the moment they
    /// open it. So the cover is made of the app's own panel tints and a basket
    /// glyph, which reads as designed instead of as missing, and stays honest
    /// about a set of dishes nobody has photographed.
    private func cover(_ plan: MealPlan) -> some View {
        ZStack {
            LinearGradient(
                colors: [tint(plan), tint(plan).opacity(0.45)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            MS.shoppingBasketFill
                .sized(34)
                .foregroundStyle(Theme.Colors.heading.opacity(0.28))
            if let range = plan.estimatedCostRange {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(range)
                            .font(BrandFont.nunito(11, 800))
                            .foregroundStyle(Theme.Colors.heading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Theme.Colors.card.opacity(0.9)))
                    }
                }
                .padding(8)
            }
        }
        .frame(height: 92)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    /// Alternates so a shelf of weeks has some rhythm, and stays put for a given
    /// plan rather than changing every time the view redraws.
    private func tint(_ plan: MealPlan) -> Color {
        abs(plan.planID.hashValue) & 1 == 0 ? Theme.Colors.sagePanel : Theme.Colors.peachPanel
    }

    private func subtitle(_ plan: MealPlan) -> String {
        let dinners = plan.mealCount == 1 ? "1 dinner" : "\(plan.mealCount) dinners"
        let items = plan.toBuy.count
        guard items > 0 else { return dinners }
        return "\(dinners), \(items == 1 ? "1 item" : "\(items) items")"
    }
}
