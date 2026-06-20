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
    @Query private var allMeals: [PlannedMeal]

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

    // Photo estimate flow
    @State private var estimatePhotoItem: PhotosPickerItem?
    @State private var isShowingCamera = false
    @State private var isEstimating = false
    @State private var estimateError: String?
    @State private var estimate: MealPhotoEstimator.Estimate?
    @State private var estimatePhotoData: Data?
    @State private var estimateTitle = ""
    @State private var estimateCalories = ""
    @State private var estimateProtein = ""
    /// nil = "just extra", otherwise the planned meal this food replaced.
    @State private var replacingMeal: PlannedMeal?

    private var availableLeftovers: [Leftover] {
        leftovers.filter { $0.servingsRemaining > 0 }
    }

    private var frequentMeals: [String] {
        ProgressStats.frequentMeals(logs: allLogs)
    }

    /// Today's still-planned meals — candidates for "this replaced dinner".
    private var replaceableMeals: [PlannedMeal] {
        let today = Calendar.current.startOfDay(for: .now)
        return allMeals
            .filter { $0.date == today && $0.status == .planned }
            .sorted { $0.mealType.sortOrder < $1.mealType.sortOrder }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    if let justLogged {
                        confirmationBanner(justLogged)
                    }
                    if LLMClient.isConfigured {
                        photoEstimateCard
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

    // MARK: - Photo estimate

    /// The McDonald's flow: snap the plate, get a name + honest calorie range,
    /// fix anything, choose whether it replaced a planned meal, log it.
    private var photoEstimateCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Snap your plate")
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                if isEstimating {
                    HStack(spacing: Theme.Spacing.sm) {
                        ProgressView()
                        Text("Sizing up your meal…")
                            .font(.gluttCaption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md)
                } else if estimate != nil {
                    estimateResult
                } else {
                    Text("Glutt estimates the meal and calories — you correct anything it gets wrong.")
                        .font(.gluttCaption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    HStack(spacing: Theme.Spacing.sm) {
                        if CameraPicker.isAvailable {
                            Button {
                                Haptics.impact(.light)
                                isShowingCamera = true
                            } label: {
                                HStack(spacing: 6) {
                                    Ph.camera.regular
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 16, height: 16)
                                    Text("Camera")
                                }
                            }
                            .buttonStyle(.gluttPillFilled)
                        }
                        PhotosPicker(selection: $estimatePhotoItem, matching: .images) {
                            HStack(spacing: 6) {
                                Ph.image.regular
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 16, height: 16)
                                Text("Photo library")
                            }
                            .font(.gluttCaption.weight(.semibold))
                        }
                        .buttonStyle(.gluttPill)
                    }
                    if let estimateError {
                        Text(estimateError)
                            .font(.gluttCaption)
                            .foregroundStyle(Theme.Colors.tomato)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .onChange(of: estimatePhotoItem) {
            guard estimatePhotoItem != nil else { return }
            Task {
                if let data = try? await estimatePhotoItem?.loadTransferable(type: Data.self) {
                    await runEstimate(data)
                }
                estimatePhotoItem = nil
            }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker { data in
                Task { await runEstimate(data) }
            }
            .ignoresSafeArea()
        }
    }

    private var estimateResult: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            TextField("Meal name", text: $estimateTitle)
                .font(.gluttHeadline)
            HStack(spacing: Theme.Spacing.sm) {
                TextField("Calories", text: $estimateCalories)
                    .keyboardType(.numberPad)
                TextField("Protein g", text: $estimateProtein)
                    .keyboardType(.numberPad)
            }
            .font(.gluttBody)

            if let range = estimate?.rangeLabel {
                Text("\(range)\(estimate?.note.map { " · \($0)" } ?? "")")
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            if !replaceableMeals.isEmpty {
                replacementPicker
            }

            HStack(spacing: Theme.Spacing.sm) {
                Button("Log it") {
                    Haptics.notify(.success)
                    logEstimate()
                }
                .buttonStyle(.gluttPrimary)
                Button("Retake") {
                    Haptics.impact(.light)
                    resetEstimate()
                }
                .buttonStyle(.gluttSecondary)
            }
        }
    }

    /// "Was this instead of dinner?" — the planned-vs-actual link.
    private var replacementPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Was this instead of a planned meal?")
                .font(.gluttCaption.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.xs) {
                    Button {
                        Haptics.selection()
                        replacingMeal = nil
                    } label: {
                        Chip(label: "Just extra", isSelected: replacingMeal == nil)
                    }
                    .buttonStyle(.plain)
                    ForEach(replaceableMeals) { meal in
                        Button {
                            Haptics.selection()
                            replacingMeal = meal
                        } label: {
                            Chip(
                                label: "Instead of \(meal.mealType.label.lowercased()) (\(meal.displayTitle))",
                                isSelected: replacingMeal === meal
                            )
                            .fixedSize()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func runEstimate(_ rawData: Data) async {
        isEstimating = true
        estimateError = nil
        guard let prepared = ImagePrep.prepareForVision(rawData) else {
            estimateError = "Couldn't read that image."
            isEstimating = false
            return
        }
        do {
            let result = try await MealPhotoEstimator.estimate(imageData: prepared)
            estimate = result
            estimatePhotoData = rawData
            estimateTitle = result.title
            estimateCalories = String(result.calories)
            estimateProtein = String(result.proteinGrams)
            replacingMeal = nil
        } catch {
            estimateError = error.localizedDescription
        }
        isEstimating = false
    }

    private func logEstimate() {
        let entry = FoodLog(
            title: estimateTitle.trimmingCharacters(in: .whitespaces),
            source: .photo,
            calories: Int(estimateCalories),
            proteinGrams: Int(estimateProtein),
            plannedMeal: replacingMeal
        )
        entry.photoData = estimatePhotoData
        if let replacingMeal {
            replacingMeal.status = .replaced
        }
        log(entry)
        resetEstimate()
    }

    private func resetEstimate() {
        estimate = nil
        estimatePhotoData = nil
        estimateTitle = ""
        estimateCalories = ""
        estimateProtein = ""
        estimateError = nil
        replacingMeal = nil
    }

    // MARK: - Sections

    private func confirmationBanner(_ title: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Ph.checkCircle.fill
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(Theme.Colors.accent)
            Text("Logged \(title)")
                .font(.gluttCaption.weight(.medium))
                .foregroundStyle(Theme.Colors.accent)
            Spacer()
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.successTint)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var quickAddCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Quick add")
            FlowChips(items: Self.quickFoods.map(\.title)) { title in
                Haptics.notify(.success)
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
                Haptics.notify(.success)
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
                    Haptics.notify(.success)
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
                        HStack(spacing: 4) {
                            Ph.forkKnife.regular
                                .resizable()
                                .scaledToFit()
                                .frame(width: 13, height: 13)
                                .foregroundStyle(Theme.Colors.accent)
                            Text("Eat one")
                                .font(.gluttCaption.weight(.medium))
                                .foregroundStyle(Theme.Colors.accent)
                        }
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
                    .onChange(of: isRestaurant) {
                        Haptics.impact(.light)
                    }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    HStack(spacing: 6) {
                        Ph.camera.regular
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                        Text(photoData == nil ? "Attach a photo" : "Photo attached ✓")
                    }
                    .font(.gluttCaption.weight(.medium))
                    .foregroundStyle(Theme.Colors.accent)
                }
                if !replaceableMeals.isEmpty {
                    replacementPicker
                }
                Button("Log it") {
                    Haptics.notify(.success)
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
            proteinGrams: Int(manualProtein),
            plannedMeal: replacingMeal
        )
        entry.photoData = photoData
        if let replacingMeal {
            replacingMeal.status = .replaced
        }
        log(entry)
        manualTitle = ""
        manualCalories = ""
        manualProtein = ""
        photoData = nil
        photoItem = nil
        isRestaurant = false
        replacingMeal = nil
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
