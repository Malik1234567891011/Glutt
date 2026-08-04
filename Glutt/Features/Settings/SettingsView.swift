import SuperwallKit
import SwiftData
import SwiftUI

/// App settings: dietary rules, the learned taste profile (visible and
/// editable — no black box), and optional AI configuration.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Query private var recipes: [Recipe]
    @Query private var sessions: [CookSession]

    @State private var calorieGoalText = ""
    @State private var proteinGoalText = ""
    @State private var allergyText = ""
    @State private var dislikeText = ""
    @State private var isShowingImportGuide = false
    @State private var isRestoring = false
    @State private var didRestorePurchases = false

    /// Optional so previews (and any host that doesn't inject it) still build.
    @Environment(AccountSession.self) private var session: AccountSession?
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false
    @State private var didDeleteAccount = false
    @State private var deleteErrorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                helpSection
                subscriptionSection
                accountSection
                nutritionSection
                tasteProfileSection
                dietarySection
                aiSection
            }
            .sheet(isPresented: $isShowingImportGuide) {
                ImportGuideView()
            }
            .alert("Purchases Restored", isPresented: $didRestorePurchases) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your Glutt Premium subscription is active.")
            }
            .alert("Delete your account?", isPresented: $isConfirmingDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete account", role: .destructive) {
                    Task { await deleteAccount() }
                }
            } message: {
                // Says plainly what survives. The subscription line matters
                // most: someone deleting an account does not expect to keep
                // being charged, and only the App Store can stop that.
                Text("""
                Your name and email are removed from Glutt's servers for good.

                Your recipes stay on this iPhone. This does not cancel your \
                subscription. Manage that in the App Store.
                """)
            }
            .alert("Account deleted", isPresented: $didDeleteAccount) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your Glutt account is gone. Your recipes are still here on this iPhone.")
            }
            .alert(
                "Couldn't delete your account",
                isPresented: Binding(
                    get: { deleteErrorMessage != nil },
                    set: { if !$0 { deleteErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteErrorMessage ?? "")
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Haptics.impact(.light)
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

    // MARK: - Help / Legal

    private var helpSection: some View {
        Section {
            Button {
                Haptics.impact(.light)
                isShowingImportGuide = true
            } label: {
                HStack {
                    Ph.export.regular
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(Theme.Colors.accent)
                    Text("How to import recipes")
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    Ph.caretRight.regular
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Button {
                Haptics.impact(.light)
                open(urlString: "https://glutt.org/privacy")
            } label: {
                phosphorRowLabel("Privacy Policy", icon: Ph.shieldCheck.regular, tint: Color.blue.opacity(0.7))
            }
            Button {
                Haptics.impact(.light)
                open(urlString: "https://glutt.org/terms")
            } label: {
                phosphorRowLabel("Terms of Service", icon: Ph.scroll.regular, tint: Color.indigo.opacity(0.7))
            }
            Button {
                Haptics.impact(.light)
                open(urlString: "https://glutt.org/support")
            } label: {
                phosphorRowLabel("Support", icon: Ph.headset.regular, tint: Theme.Colors.accent)
            }
        }
    }

    private func open(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        openURL(url)
    }

    private func phosphorRowLabel(_ text: String, icon: Image, tint: Color) -> some View {
        HStack {
            icon
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(tint)
            Text(text)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Ph.arrowSquareOut.regular
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    // MARK: - Subscription / Restore Purchases

    private var subscriptionSection: some View {
        Section {
            Button {
                Haptics.impact(.medium)
                Task { await restorePurchases() }
            } label: {
                HStack {
                    Ph.arrowClockwise.regular
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(Theme.Colors.accent)
                    Text("Restore Purchases")
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    if isRestoring {
                        ProgressView()
                    }
                }
            }
            .disabled(isRestoring)
        } header: {
            Text("Subscription")
        } footer: {
            Text("Glutt Premium unlocks AI recipe invention. Already subscribed? Restore your purchase here. Manage or cancel anytime in the App Store.")
        }
    }

    /// Restores a previous Glutt Premium purchase on user request (App Store
    /// guideline 3.1.1). In Superwall's automatic mode, the SDK surfaces its own
    /// alert when no active subscription is found, so we only confirm the success
    /// path here to avoid showing two alerts.
    @MainActor
    private func restorePurchases() async {
        isRestoring = true
        _ = await Superwall.shared.restorePurchases()
        isRestoring = false
        if Superwall.shared.subscriptionStatus.isActive {
            didRestorePurchases = true
        }
    }

    // MARK: - Account

    /// Sign out and delete. The delete path is not optional: Apple requires an
    /// in-app way to remove an account from any app that lets you create one
    /// (App Review 5.1.1(v)), and hiding it is a rejection.
    ///
    /// Signing out does not lock the app — entitlement comes from the Apple ID,
    /// not from having an account.
    @ViewBuilder private var accountSection: some View {
        if let session {
            Section {
                switch session.state {
                case let .signedIn(_, email):
                    HStack {
                        // No person glyph in the vendored Phosphor subset, and
                        // the chef hat is more Glutt anyway.
                        Ph.chefHat.regular
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .foregroundStyle(Theme.Colors.accent)
                        Text(email ?? "Signed in")
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Button {
                        Haptics.impact(.light)
                        Task { await session.signOut() }
                    } label: {
                        Text("Sign out")
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }

                    Button(role: .destructive) {
                        Haptics.impact(.medium)
                        isConfirmingDelete = true
                    } label: {
                        HStack {
                            Text("Delete account")
                            Spacer()
                            if isDeleting { ProgressView() }
                        }
                    }
                    .disabled(isDeleting)

                default:
                    Text("Not signed in")
                        .font(.gluttCaption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            } header: {
                Text("Account")
            } footer: {
                Text("Your account is how Glutt recognizes you on a new phone. Recipes live on this device either way.")
            }
        }
    }

    private func deleteAccount() async {
        guard let session else { return }
        isDeleting = true
        do {
            try await session.deleteAccount()
            didDeleteAccount = true
        } catch {
            deleteErrorMessage = "Something went wrong on our end. Please try again, or contact support if it keeps happening."
            Analytics.capture(.accountDeleteFailed, ["detail": error.localizedDescription])
        }
        isDeleting = false
    }

    // MARK: - Nutrition

    private var nutritionSection: some View {
        Section {
            Picker("Mode", selection: Binding(
                get: { prefs.nutritionMode },
                set: { newValue in
                    Haptics.selection()
                    prefs.nutritionMode = newValue
                }
            )) {
                ForEach(NutritionMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if prefs.nutritionMode.showsNutrition {
                HStack {
                    Ph.flame.regular
                        .resizable()
                        .scaledToFit()
                        .frame(width: 15, height: 15)
                        .foregroundStyle(Theme.Colors.tomato)
                    Text("Daily calories")
                    Spacer()
                    TextField("e.g. 2400", text: $calorieGoalText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
                HStack {
                    Ph.lightning.regular
                        .resizable()
                        .scaledToFit()
                        .frame(width: 15, height: 15)
                        .foregroundStyle(Color.orange.opacity(0.8))
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

    // MARK: - Taste Profile

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
                                    Haptics.impact(.light)
                                    prefs.tasteProfile.removeAll { $0 == descriptor }
                                } label: {
                                    Ph.xCircle.fill
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 13, height: 13)
                                        .foregroundStyle(Theme.Colors.textSecondary)
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
            Button {
                Haptics.impact(.light)
                // Bundled chef and restaurant dishes ship with every install, so
                // they'd skew the profile toward content the user never chose.
                prefs.tasteProfile = TasteProfileBuilder.descriptors(
                    recipes: recipes.filter { !$0.isCuratedRecipe },
                    sessions: sessions
                )
            } label: {
                HStack {
                    Ph.arrowsClockwise.regular
                        .resizable()
                        .scaledToFit()
                        .frame(width: 15, height: 15)
                        .foregroundStyle(Theme.Colors.accent)
                    Text("Refresh from my cooking history")
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
            }
        } header: {
            Text("You seem to love")
        } footer: {
            Text("Built from your ratings, repeats, and saves. Used to rank suggestions. Remove anything that's wrong.")
        }
    }

    // MARK: - Food Rules / Dietary

    private var dietarySection: some View {
        Section {
            ForEach(DietaryRule.allCases) { rule in
                Toggle(rule.label, isOn: Binding(
                    get: { prefs.dietaryRules.contains(rule) },
                    set: { isOn in
                        Haptics.impact(.light)
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
                Ph.warning.regular
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .foregroundStyle(Color.orange.opacity(0.85))
                Text("Allergies")
                Spacer()
                TextField("peanuts, shellfish…", text: $allergyText)
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Ph.thumbsDown.regular
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .foregroundStyle(Theme.Colors.textSecondary)
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

    // MARK: - AI

    private var aiSection: some View {
        Section {
            if LLMClient.isConfigured {
                HStack(spacing: 6) {
                    Ph.sparkle.regular
                        .resizable()
                        .scaledToFit()
                        .frame(width: 15, height: 15)
                        .foregroundStyle(Theme.Colors.accent)
                    Text("AI features enabled (secured backend)")
                        .font(.gluttCaption)
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
        } header: {
            Text("AI")
        } footer: {
            Text(LLMClient.isConfigured
                ? "AI powers imports, pantry/photo analysis, smart suggestions, and recipe adjustments. We send only what is needed for each request."
                : "AI is currently unavailable. Glutt still works with offline heuristics for core flows.")
        }
    }
}
