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

    var body: some View {
        NavigationStack {
            Form {
                tasteProfileSection
                dietarySection
                aiSection
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
                        dismiss()
                    }
                }
            }
        }
    }

    private var prefs: UserPrefs {
        UserPrefs.current(in: context)
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
        Section("Dietary rules") {
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
        }
    }

    private var aiSection: some View {
        Section {
            SecureField("API key", text: $apiKey)
            TextField("Model", text: $model)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if LLMClient.isConfigured {
                Label("AI features enabled", systemImage: "sparkles")
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.accent)
            }
        } header: {
            Text("AI (optional)")
        } footer: {
            Text("Everything in Glutt works without this. An OpenAI-compatible key upgrades search, substitutions, and suggestions over time.")
        }
    }
}
