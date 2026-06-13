import SwiftData
import SwiftUI

/// App settings: dietary rules, the learned taste profile (visible and
/// editable — no black box), and optional AI configuration.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var recipes: [Recipe]
    @Query private var sessions: [CookSession]

    @State private var apiKey = LLMClient.apiKey
    @State private var model = LLMClient.model
    @State private var calorieGoalText = ""
    @State private var proteinGoalText = ""
    @State private var allergyText = ""
    @State private var dislikeText = ""
    @State private var isShowingImportGuide = false

    var body: some View {
        NavigationStack {
            Form {
                helpSection
                nutritionSection
                tasteProfileSection
                dietarySection
                aiSection
            }
            .sheet(isPresented: $isShowingImportGuide) {
                ImportGuideView()
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        LLMClient.apiKey = apiKey
                        LLMClient.model = model
                        prefs.dailyCalorieGoal = Int(calorieGoalText)
                        prefs.dailyProteinGoal = Int(proteinGoalText)
                        prefs.allergies = splitList(allergyText)
                        prefs.dislikedIngredients = splitList(dislikeText)
                        dismiss()
                    }
                }
            }
        }
    }

    private var prefs: UserPrefs {
        UserPrefs.current(in: context)
    }

    private var helpSection: some View {
        Section {
            Button {
                isShowingImportGuide = true
            } label: {
                HStack {
                    Label("How to import recipes", systemImage: "square.and.arrow.up")
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
    }

    private var nutritionSection: some View {
        Section {
            Picker("Mode", selection: Binding(
                get: { prefs.nutritionMode },
                set: { prefs.nutritionMode = $0 }
            )) {
                ForEach(NutritionMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if prefs.nutritionMode.showsNutrition {
                HStack {
                    Text("Daily calories")
                    Spacer()
                    TextField("e.g. 2400", text: $calorieGoalText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
                HStack {
                    Text("Daily protein (g)")
                    Spacer()
                    TextField("e.g. 160", text: $proteinGoalText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
            }
        } header: {
            Text("Nutrition")
        } footer: {
            Text(prefs.nutritionMode == .cookingOnly
                ? "Just cooking: no calories, no macros, anywhere. Switch anytime."
                : "Goals show on Today and Progress. Estimates are ranges — treat them as direction, not gospel.")
        }
        .onAppear {
            calorieGoalText = prefs.dailyCalorieGoal.map(String.init) ?? ""
            proteinGoalText = prefs.dailyProteinGoal.map(String.init) ?? ""
        }
    }

    private var tasteProfileSection: some View {
        Section {
            if prefs.tasteProfile.isEmpty {
                Text("Cook and rate a few recipes and Glutt will learn what you like.")
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(prefs.tasteProfile, id: \.self) { descriptor in
                            HStack(spacing: 4) {
                                Text(descriptor)
                                Button {
                                    prefs.tasteProfile.removeAll { $0 == descriptor }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption2)
                                }
                            }
                            .font(.gluttCaption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.Colors.accent.opacity(0.1))
                            .clipShape(Capsule())
                            .fixedSize()
                        }
                    }
                }
            }
            Button("Refresh from my cooking history") {
                prefs.tasteProfile = TasteProfileBuilder.descriptors(recipes: recipes, sessions: sessions)
            }
        } header: {
            Text("You seem to love")
        } footer: {
            Text("Built from your ratings, repeats, and saves. Used to rank suggestions. Remove anything that's wrong.")
        }
    }

    private var dietarySection: some View {
        Section {
            ForEach(DietaryRule.allCases) { rule in
                Toggle(rule.label, isOn: Binding(
                    get: { prefs.dietaryRules.contains(rule) },
                    set: { isOn in
                        if isOn {
                            prefs.dietaryRules.append(rule)
                        } else {
                            prefs.dietaryRules.removeAll { $0 == rule }
                        }
                    }
                ))
                .tint(Theme.Colors.accent)
            }
            HStack {
                Text("Allergies")
                Spacer()
                TextField("peanuts, shellfish…", text: $allergyText)
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Text("Dislikes")
                Spacer()
                TextField("cilantro, olives…", text: $dislikeText)
                    .multilineTextAlignment(.trailing)
            }
        } header: {
            Text("Food rules")
        } footer: {
            Text("Respected in suggestions, planning, and substitutions. Allergies always get a hard warning on recipes. Comma-separated.")
        }
        .onAppear {
            allergyText = prefs.allergies.joined(separator: ", ")
            dislikeText = prefs.dislikedIngredients.joined(separator: ", ")
        }
    }

    private func splitList(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var aiSection: some View {
        Section {
            if LLMClient.usesEmbeddedKey {
                Label("AI enabled (beta)", systemImage: "sparkles")
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.accent)
            }
            SecureField("API key (optional override)", text: $apiKey)
            TextField("Model", text: $model)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if LLMClient.isConfigured && !LLMClient.usesEmbeddedKey {
                Label("AI features enabled (your key)", systemImage: "sparkles")
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.accent)
            }
        } header: {
            Text("AI")
        } footer: {
            Text(LLMClient.isConfigured
                ? "AI powers import cleanup, \"just tell me\" suggestions, and smarter explanations. Everything still works offline."
                : "Everything in Glutt works without this. An OpenAI-compatible key upgrades imports, search, and suggestions.")
        }
    }
}
