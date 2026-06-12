import PhotosUI
import SwiftData
import SwiftUI

/// Log food in under ten seconds: quick-add chips, your frequent meals,
/// leftovers in the fridge, or a manual entry. Estimates are ranges,
/// corrections are always one tap away.
struct LogFoodView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FoodLog.timestamp, order: .reverse) private var allLogs: [FoodLog]
    @Query private var leftovers: [Leftover]

    /// Common foods with rough nutrition — one tap to log.
    private static let quickFoods: [(title: String, calories: Int, protein: Int)] = [
        ("2 eggs", 156, 13), ("Protein shake", 160, 30), ("Greek yogurt", 150, 15),
        ("Oatmeal bowl", 300, 10), ("Coffee with milk", 40, 2), ("Banana", 105, 1),
        ("Rice bowl", 400, 12), ("Chicken wrap", 450, 30), ("PB toast", 290, 11),
    ]

    @State private var manualTitle = ""
    @State private var manualCalories = ""
    @State private var manualProtein = ""
    @State private var isRestaurant = false
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var justLogged: String?

    private var availableLeftovers: [Leftover] {
        leftovers.filter { $0.servingsRemaining > 0 }
    }

    private var frequentMeals: [String] {
        ProgressStats.frequentMeals(logs: allLogs)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    if let justLogged {
                        confirmationBanner(justLogged)
                    }
                    quickAddCard
                    if !frequentMeals.isEmpty {
                        frequentsCard
                    }
                    if !availableLeftovers.isEmpty {
                        leftoversCard
                    }
                    manualCard
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Log food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private func confirmationBanner(_ title: String) -> some View {
        Label("Logged \(title)", systemImage: "checkmark.circle.fill")
            .font(.gluttCaption.weight(.medium))
            .foregroundStyle(Theme.Colors.accent)
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.successTint)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var quickAddCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Quick add")
            FlowChips(items: Self.quickFoods.map(\.title)) { title in
                guard let food = Self.quickFoods.first(where: { $0.title == title }) else { return }
                log(FoodLog(
                    title: food.title,
                    source: .quickAdd,
                    calories: food.calories,
                    proteinGrams: food.protein
                ))
            }
        }
    }

    private var frequentsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "You often eat")
            FlowChips(items: frequentMeals) { title in
                // Repeat the most recent log of the same meal, nutrition included.
                let previous = allLogs.first { $0.title == title }
                log(FoodLog(
                    title: title,
                    source: previous?.source ?? .quickAdd,
                    calories: previous?.calories,
                    proteinGrams: previous?.proteinGrams
                ))
            }
        }
    }

    private var leftoversCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Leftovers in the fridge")
            ForEach(availableLeftovers) { leftover in
                Button {
                    logLeftover(leftover)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(leftover.title)
                                .font(.gluttBody)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text("\(leftover.servingsRemaining.formatted()) servings left")
                                .font(.gluttCaption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Spacer()
                        Label("Eat one", systemImage: "fork.knife")
                            .font(.gluttCaption.weight(.medium))
                            .foregroundStyle(Theme.Colors.accent)
                    }
                }
                .buttonStyle(.plain)
                .cardStyle()
            }
        }
    }

    private var manualCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Something else")
            VStack(spacing: Theme.Spacing.sm) {
                TextField("What did you eat?", text: $manualTitle)
                    .font(.gluttBody)
                HStack(spacing: Theme.Spacing.sm) {
                    TextField("Calories (optional)", text: $manualCalories)
                        .keyboardType(.numberPad)
                    TextField("Protein g (optional)", text: $manualProtein)
                        .keyboardType(.numberPad)
                }
                .font(.gluttBody)
                Toggle("Restaurant / takeout", isOn: $isRestaurant)
                    .font(.gluttBody)
                    .tint(Theme.Colors.accent)
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(photoData == nil ? "Attach a photo" : "Photo attached ✓", systemImage: "camera")
                        .font(.gluttCaption.weight(.medium))
                        .foregroundStyle(Theme.Colors.accent)
                }
                Button("Log it") {
                    logManual()
                }
                .buttonStyle(.gluttPrimary)
                .disabled(manualTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .cardStyle()
        }
        .onChange(of: photoItem) {
            Task {
                photoData = try? await photoItem?.loadTransferable(type: Data.self)
            }
        }
    }

    // MARK: - Actions

    private func log(_ entry: FoodLog) {
        context.insert(entry)
        withAnimation { justLogged = entry.title }
    }

    private func logLeftover(_ leftover: Leftover) {
        let entry = FoodLog(
            title: leftover.title,
            source: .leftover,
            calories: leftover.caloriesPerServing,
            proteinGrams: leftover.proteinPerServing,
            leftover: leftover
        )
        leftover.servingsRemaining = max(0, leftover.servingsRemaining - 1)
        log(entry)
    }

    private func logManual() {
        let entry = FoodLog(
            title: manualTitle.trimmingCharacters(in: .whitespaces),
            source: isRestaurant ? .restaurant : .manual,
            calories: Int(manualCalories),
            proteinGrams: Int(manualProtein)
        )
        entry.photoData = photoData
        log(entry)
        manualTitle = ""
        manualCalories = ""
        manualProtein = ""
        photoData = nil
        photoItem = nil
        isRestaurant = false
    }
}

/// Simple wrapping chip grid used by quick-add sections.
struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: Theme.Spacing.sm)], spacing: Theme.Spacing.sm) {
            ForEach(items, id: \.self) { item in
                Button {
                    onTap(item)
                } label: {
                    Text(item)
                        .font(.gluttCaption.weight(.medium))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .padding(.horizontal, Theme.Spacing.xs)
                        .background(Theme.Colors.card)
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Theme.Colors.border))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
