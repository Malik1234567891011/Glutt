import SwiftData
import SwiftUI

/// Polly, at the bottom of a lesson.
///
/// Deliberately *not* a second chat screen. The lesson is the teaching and this
/// is the follow up question, so it lives inline underneath the text rather
/// than behind a button that opens `RecipeChatView`'s full transcript UI: a
/// sheet on top of a sheet, for one question, is how a small feature starts
/// feeling like an errand.
///
/// So there is no thread scrollback, no clear button and no proposal cards.
/// Turns are still persisted (`RecipeChatMessage`, keyed `skill:<id>`), so
/// closing the lesson and coming back keeps the answer.
struct SkillAskPollyView: View {
    let skill: Skill

    @Environment(\.modelContext) private var context

    /// Filtered to this skill's thread. A `@Query` rather than a fetch so an
    /// appended turn draws itself.
    @Query private var messages: [RecipeChatMessage]

    @State private var draft = ""
    @State private var isThinking = false
    @State private var failure: String?
    @FocusState private var isWriting: Bool

    init(skill: Skill) {
        self.skill = skill
        let key = SkillChatService.familyKey(for: skill)
        _messages = Query(
            filter: #Predicate<RecipeChatMessage> { $0.familyKey == key },
            sort: \.createdAt,
            order: .forward
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            ForEach(messages) { message in
                turn(message)
            }

            if isThinking {
                HStack(spacing: 8) {
                    SkillTypingDots()
                    Text("Polly is thinking")
                        .font(BrandFont.nunito(13, 600))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .padding(.vertical, 4)
            }

            if let failure {
                Text(failure)
                    .font(BrandFont.nunito(13, 600))
                    .foregroundStyle(Theme.Colors.tomato)
            }

            // The chips retire once the conversation has started. Leaving them
            // under a real answer turns a conversation back into a menu.
            if messages.isEmpty && !isThinking {
                chips
            }

            composer
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous)
                .strokeBorder(Theme.Colors.border, lineWidth: 1.5)
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image("bearThinking")
                .resizable()
                .scaledToFit()
                .frame(height: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ask Polly")
                    .font(BrandFont.nunito(15, 800))
                    .foregroundStyle(Theme.Colors.heading)
                Text("She knows this lesson. Ask her anything about it.")
                    .font(BrandFont.nunito(12.5, 600))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var chips: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(SkillChatService.suggestions(for: skill), id: \.self) { chip in
                Button { send(chip) } label: {
                    HStack(spacing: 7) {
                        Text(chip)
                            .font(BrandFont.nunito(13.5, 700))
                            .foregroundStyle(Theme.Colors.accent)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.Colors.accent.opacity(0.7))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Capsule().fill(Theme.Colors.greenTint))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func turn(_ message: RecipeChatMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(BrandFont.nunito(14.5, 600))
                    .foregroundStyle(Theme.Colors.creamText)
                    .padding(.horizontal, 13).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.Colors.accent))
            }
        case .assistant:
            Text(message.text)
                .font(BrandFont.nunito(14.5, 600))
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 13).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.Colors.surface2))
                .padding(.trailing, 20)
        }
    }

    private var composer: some View {
        HStack(spacing: 9) {
            TextField("Ask about this skill", text: $draft, axis: .vertical)
                .font(BrandFont.nunito(14.5, 600))
                .lineLimit(1 ... 4)
                .focused($isWriting)
                .submitLabel(.send)
                .onSubmit { send(draft) }
                .padding(.horizontal, 13).padding(.vertical, 10)
                .background(Capsule().fill(Theme.Colors.surface2))

            Button { send(draft) } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.Colors.creamText)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(canSend ? Theme.Colors.accent : Theme.Colors.muted))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
    }

    private var canSend: Bool {
        !isThinking && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isThinking else { return }

        let family = SkillChatService.familyKey(for: skill)
        // History is read before the question is appended: the question goes on
        // the wire as the live turn, and sending it twice would have Polly
        // answering an echo.
        let history = RecipeChatStore.messages(family: family, in: context)
        RecipeChatStore.append(role: .user, text: question, family: family, in: context)

        draft = ""
        isWriting = false
        failure = nil
        isThinking = true
        Analytics.capture(.aiToolUsed, ["tool": "skill_chat", "category": skill.categoryID])

        let prefs = UserPrefs.current(in: context)
        Task { @MainActor in
            defer { isThinking = false }
            do {
                let reply = try await SkillChatService.reply(
                    to: question,
                    skill: skill,
                    history: history,
                    prefs: prefs
                )
                RecipeChatStore.append(role: .assistant, text: reply, family: family, in: context)
            } catch {
                failure = "Polly couldn't answer that one. Try again in a moment."
            }
        }
    }
}

/// A local copy rather than a shared component. `RecipeChatView`'s is private
/// to that file, and three dots is less code than the indirection needed to
/// share it.
private struct SkillTypingDots: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0 ..< 3, id: \.self) { index in
                Circle()
                    .fill(Theme.Colors.muted)
                    .frame(width: 6, height: 6)
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
