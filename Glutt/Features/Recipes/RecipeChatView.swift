import SwiftData
import SwiftUI

/// Ask Polly about a dish, in text, before you cook it.
///
/// Replaces the old "Make it…" and "Use what I have" pills: both are chips in
/// here now. Answers are just answers — nothing touches the library until the
/// cook taps Apply on a proposal, which mints a version through the same path
/// `AdjustRecipeView` always used.
struct RecipeChatView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var pantryItems: [PantryItem]
    @Query private var ownedTools: [KitchenTool]
    @Query private var messages: [RecipeChatMessage]

    let recipe: Recipe
    /// The serving count the detail screen is currently showing, so amounts in
    /// an answer match the amounts on the screen behind this sheet.
    let servings: Int
    /// Handed the version Apply created, so the detail screen can land on it.
    let onApply: (Recipe) -> Void

    private let familyKey: String

    @State private var draft = ""
    @State private var isThinking = false
    /// Flips two seconds in, so a rewrite doesn't sit under three dots looking dead.
    @State private var isSlow = false
    @State private var errorText: String?
    /// The turn to re-send if the cook taps Try again. Its question is already
    /// in the thread; only the call failed.
    @State private var retryQuestion: String?
    @State private var retryHistory: [RecipeChatMessage] = []
    @FocusState private var inputFocused: Bool

    /// `prefill` seeds the input rather than sending it, so a cook arriving from
    /// the substitute sheet can add "and I've only got thighs" before hitting send.
    init(recipe: Recipe, servings: Int, prefill: String? = nil, onApply: @escaping (Recipe) -> Void) {
        self.recipe = recipe
        self.servings = servings
        self.onApply = onApply
        _draft = State(initialValue: prefill ?? "")
        let key = RecipeChatStore.familyKey(for: recipe)
        familyKey = key
        _messages = Query(
            filter: #Predicate<RecipeChatMessage> { $0.familyKey == key },
            sort: \RecipeChatMessage.createdAt,
            order: .forward
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if messages.isEmpty { greeting }
                        ForEach(messages) { message in
                            bubble(message).id(message.persistentModelID)
                        }
                        if isThinking { thinkingBubble }
                        if let errorText { errorBubble(errorText) }
                        if messages.isEmpty { chips }
                        Color.clear.frame(height: 1).id(Self.bottomAnchor)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { scrollToEnd(proxy) }
                .onChange(of: isThinking) { scrollToEnd(proxy) }
                .onChange(of: errorText) { scrollToEnd(proxy) }
            }
            .background(Theme.Colors.background)
            .safeAreaInset(edge: .bottom) { inputBar }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { titleBar }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if !messages.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Clear conversation", systemImage: "trash", role: .destructive) {
                                RecipeChatStore.clear(family: familyKey, in: context)
                                errorText = nil
                            }
                        } label: {
                            MS.moreHoriz.sized(20).foregroundStyle(Theme.Colors.heading)
                        }
                    }
                }
            }
        }
        .onAppear {
            RecipeChatStaging.seedIfRequested(family: familyKey, in: context)
            Analytics.capture(.aiToolUsed, ["tool": "recipe_chat_opened"])
            if !draft.isEmpty { inputFocused = true }
        }
        // `-chatScreen applied`: taps Apply for you, through the real method, so
        // the dismiss-then-push can be seen. Inert without the launch argument.
        .task {
            guard RecipeChatStaging.requested == .applied else { return }
            try? await Task.sleep(for: RecipeChatStaging.beat)
            guard !Task.isCancelled,
                  let message = messages.last, let proposal = message.proposal,
                  message.appliedLabel == nil
            else { return }
            apply(message, proposal)
        }
    }

    private static let bottomAnchor = "recipeChatBottom"

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
        }
    }

    // MARK: - Header

    private var titleBar: some View {
        HStack(spacing: 9) {
            RecipeImageView(recipe: recipe)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: -1) {
                Text("Ask Polly")
                    .font(BrandFont.nunito(14.5, 800))
                    .foregroundStyle(Theme.Colors.heading)
                Text(recipe.title)
                    .font(BrandFont.nunito(11.5, 600))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Empty state

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ask me anything about this one.")
                .font(BrandFont.bricolage(20, 700))
                .foregroundStyle(Theme.Colors.heading)
            Text("Missing an ingredient, need it to fit your rules, or just not sure about a step. I can answer, or rewrite the recipe for you.")
                .font(BrandFont.nunito(14, 600))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.bottom, 4)
    }

    private var chips: some View {
        FlowLayout(hSpacing: 8, vSpacing: 8) {
            ForEach(RecipeChatService.suggestions(chatContext)) { suggestion in
                Button {
                    Haptics.impact(.light)
                    inputFocused = false
                    switch suggestion.action {
                    case .ask(let text): send(text)
                    case .pantryPlan: runPantryPlan()
                    }
                } label: {
                    Text(suggestion.label)
                        .font(BrandFont.nunito(13.5, 700))
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Capsule().fill(Theme.Colors.accent.opacity(0.10)))
                        .overlay(Capsule().strokeBorder(Theme.Colors.accent.opacity(0.22), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Bubbles

    @ViewBuilder
    private func bubble(_ message: RecipeChatMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 44)
                Text(message.text)
                    .font(BrandFont.nunito(15, 600))
                    .foregroundStyle(Theme.Colors.creamText)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.Colors.accent))
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 10) {
                Text(message.text)
                    .font(BrandFont.nunito(15, 600))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.Colors.card))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.Colors.border, lineWidth: 1.5))
                if let proposal = message.proposal {
                    proposalCard(message, proposal)
                }
            }
            .padding(.trailing, 28)
        }
    }

    private var thinkingBubble: some View {
        HStack(spacing: 8) {
            TypingDots()
            if isSlow {
                Text("rewriting the recipe…")
                    .font(BrandFont.nunito(13, 600))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.Colors.card))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Theme.Colors.border, lineWidth: 1.5))
        .task {
            isSlow = false
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { isSlow = true }
        }
    }

    private func errorBubble(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(BrandFont.nunito(14, 600))
                .foregroundStyle(Theme.Colors.textPrimary)
            if let retryQuestion {
                Button {
                    Haptics.impact(.light)
                    run(question: retryQuestion, history: retryHistory)
                } label: {
                    Text("Try again")
                        .font(BrandFont.nunito(13.5, 800))
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Theme.Colors.background.opacity(0.7)))
                        .overlay(Capsule().strokeBorder(Theme.Colors.accent.opacity(0.35), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.Colors.warningTint))
        .padding(.trailing, 28)
    }

    // MARK: - Proposal card

    private func proposalCard(_ message: RecipeChatMessage, _ proposal: RecipeChatProposal) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 7) {
                MS.autoAwesomeFill.sized(15).foregroundStyle(Theme.Colors.accent)
                Text(proposal.versionLabel)
                    .font(BrandFont.nunito(14, 800))
                    .foregroundStyle(Theme.Colors.accent)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(proposal.changes.prefix(5), id: \.self) { change in
                    HStack(alignment: .top, spacing: 7) {
                        Text("•").font(BrandFont.nunito(14, 700)).foregroundStyle(Theme.Colors.muted)
                        Text(change)
                            .font(BrandFont.nunito(13.5, 600))
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                }
                if proposal.changes.count > 5 {
                    Text("and \(proposal.changes.count - 5) more")
                        .font(BrandFont.nunito(12.5, 700))
                        .foregroundStyle(Theme.Colors.muted)
                }
            }
            if let applied = message.appliedLabel {
                HStack(spacing: 6) {
                    MS.checkCircleFill.sized(15).foregroundStyle(Theme.Colors.accent)
                    Text("Saved as \(applied)")
                        .font(BrandFont.nunito(13, 700))
                        .foregroundStyle(Theme.Colors.accent)
                }
            } else {
                Button("Apply") { apply(message, proposal) }
                    .buttonStyle(.gluttPrimary)
            }
            Text("Saves as a new version. The original stays exactly as it is.")
                .font(BrandFont.nunito(11.5, 600))
                .foregroundStyle(Theme.Colors.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Input

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isThinking
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask about this recipe", text: $draft, axis: .vertical)
                .font(BrandFont.nunito(15, 600))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1...5)
                .focused($inputFocused)
                .padding(.horizontal, 15).padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 21, style: .continuous).fill(Theme.Colors.card))
                .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous)
                    .strokeBorder(Theme.Colors.border, lineWidth: 1.5))
            Button {
                Haptics.impact(.light)
                send(draft)
            } label: {
                MS.send.sized(18)
                    .foregroundStyle(Theme.Colors.creamText)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(canSend ? Theme.Colors.accent : Theme.Colors.mutedSoft))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Theme.Colors.background)
    }

    // MARK: - Sending

    private var chatContext: RecipeChatService.Context {
        RecipeChatService.Context(
            recipe: recipe,
            servings: servings,
            pantryMatch: PantryMatcher.match(recipe: recipe, pantry: pantryItems),
            prefs: UserPrefs.current(in: context),
            ownedTools: ownedTools
        )
    }

    private func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isThinking else { return }
        // Captured before the append, so the just-typed turn isn't in the
        // history AND the final user message.
        let history = Array(messages)
        RecipeChatStore.append(role: .user, text: question, family: familyKey, in: context)
        draft = ""
        run(question: question, history: history)
    }

    private func run(question: String, history: [RecipeChatMessage]) {
        retryQuestion = question
        retryHistory = history
        errorText = nil
        isThinking = true
        Task {
            do {
                let envelope = try await RecipeChatService.reply(
                    to: question,
                    context: chatContext,
                    history: history
                )
                RecipeChatStore.append(
                    role: .assistant,
                    text: envelope.reply,
                    proposal: envelope.proposal,
                    family: familyKey,
                    in: context
                )
                retryQuestion = nil
                retryHistory = []
                Analytics.capture(.aiToolUsed, [
                    "tool": "recipe_chat",
                    "proposed": envelope.proposal != nil,
                ])
            } catch {
                Haptics.notify(.error)
                errorText = (error as? LocalizedError)?.errorDescription
                    ?? "Couldn't reach the kitchen. Check your connection and try again."
            }
            isThinking = false
        }
    }

    /// The one chip that never leaves the phone.
    private func runPantryPlan() {
        let prefs = UserPrefs.current(in: context)
        let plan = RecipeOptimizer.plan(
            for: recipe,
            pantry: pantryItems,
            rules: prefs.dietaryRules,
            allergies: prefs.allergies
        )
        RecipeChatStore.append(role: .user, text: "Use what I have", family: familyKey, in: context)
        RecipeChatStore.append(
            role: .assistant,
            text: RecipeChatService.pantryReply(for: plan),
            proposal: RecipeChatService.pantryProposal(for: recipe, plan: plan),
            family: familyKey,
            in: context
        )
        Analytics.capture(.aiToolUsed, ["tool": "recipe_chat_pantry"])
    }

    // MARK: - Apply

    private func apply(_ message: RecipeChatMessage, _ proposal: RecipeChatProposal) {
        let outcome = RecipeChatApply.run(
            proposal,
            on: message,
            recipe: recipe,
            servings: servings,
            pantry: pantryItems,
            prefs: UserPrefs.current(in: context),
            context: context
        )
        guard case .created(let created) = outcome else {
            errorText = RecipeChatApply.staleMessage
            return
        }
        Haptics.notify(.success)
        Analytics.capture(.aiToolUsed, [
            "tool": "recipe_chat_applied",
            "pantry_plan": proposal.isPantryPlan,
        ])
        onApply(created)
    }
}

/// Three dots, breathing. The whole feedback budget for a wait that is usually
/// under two seconds.
private struct TypingDots: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Theme.Colors.muted)
                    .frame(width: 7, height: 7)
                    .opacity(phase == index ? 1 : 0.3)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(320))
                withAnimation(.easeInOut(duration: 0.25)) { phase = (phase + 1) % 3 }
            }
        }
    }
}
