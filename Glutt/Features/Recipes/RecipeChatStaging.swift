import Foundation
import SwiftData

/// Staging hook for the recipe chat: `-chatScreen empty|thread|proposal`.
///
/// Pair it with `-uiPreview -seed -openRecipe`, which lands on a recipe with the
/// paywall bypassed and no StoreKit dialog in the way.
///
/// The chat's interesting states all sit behind a network round trip and a
/// finger, and neither is available in the simulator here, so without this the
/// bubbles, the proposal card, and the Apply receipt could only be checked by
/// eye on a device. It seeds the real store and opens the real sheet: what you
/// see is what ships.
///
/// Launch arguments do not survive a TestFlight or App Store upload, so this is
/// inert everywhere but a locally run build. Same contract as
/// `ImportScreenStaging`.
enum RecipeChatStaging {

    enum Scenario: String {
        /// Greeting and the opening chips.
        case empty
        /// One exchange, no rewrite offered.
        case thread
        /// An exchange ending in an unapplied proposal card.
        case proposal
        /// Same as `proposal`, then taps Apply for you a beat later. Verifies
        /// the part no unit test reaches: Apply dismisses the sheet and the
        /// detail screen pushes the version that was just created.
        case applied
        /// Opens the diet-conflict substitute sheet, then follows its
        /// "Ask Polly about this instead" link. Verifies the sheet-to-sheet
        /// handoff and that the chat opens with the question already typed.
        case substitute
        /// Sends a real question to the real proxy. The only scenario that
        /// costs money, and the only one that proves the prompt survives
        /// contact with the model and the envelope actually parses.
        case ask
    }

    /// The question `ask` sends. Phrased to invite a rewrite, so one call
    /// exercises both halves of the envelope.
    static let liveQuestion = "I don't eat pork and I'm missing a couple of things. Can you fix the recipe for me?"

    static var requested: Scenario? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-chatScreen") else { return nil }
        guard arguments.indices.contains(flagIndex + 1),
              let scenario = Scenario(rawValue: arguments[flagIndex + 1])
        else { return .empty }
        return scenario
    }

    /// Fires once per launch. Applying pushes a *second* detail screen, and
    /// without this it would open its own chat over the version you were meant
    /// to see, hiding the thing the scenario exists to show.
    @MainActor private static var didStage = false

    /// Whether this detail screen should open the chat as it appears.
    /// `substitute` starts on the conflict sheet instead and arrives at the chat
    /// through the link, which is the thing being checked.
    @MainActor
    static func shouldOpenChatOnAppear() -> Bool {
        guard let requested, requested != .substitute, !didStage else { return false }
        didStage = true
        return true
    }

    @MainActor
    static func shouldOpenSubstituteSheetOnAppear() -> Bool {
        guard requested == .substitute, !didStage else { return false }
        didStage = true
        return true
    }

    /// How long a staged scenario waits before driving itself, so the screen it
    /// starts on is on display long enough to capture first.
    static let beat: Duration = .seconds(1.5)

    /// Writes the canned turns, once. Re-entrant because `onAppear` is.
    static func seedIfRequested(family: String, in context: ModelContext) {
        guard let scenario = requested,
              scenario != .empty, scenario != .substitute, scenario != .ask
        else { return }
        guard RecipeChatStore.messages(family: family, in: context).isEmpty else { return }

        RecipeChatStore.append(
            role: .user,
            text: "I don't have prosciutto and I don't eat pork. What can I use?",
            family: family,
            in: context
        )

        switch scenario {
        case .empty, .substitute, .ask:
            break
        case .thread:
            RecipeChatStore.append(
                role: .assistant,
                text: """
                Beef bacon or turkey bacon both work here. Render them a little harder than \
                prosciutto, because they carry less fat, and you'll get the same salty crunch \
                through the dish.
                """,
                family: family,
                in: context
            )
        case .proposal, .applied:
            RecipeChatStore.append(
                role: .assistant,
                text: "Beef bacon is the closest match. I've put a version together for you.",
                proposal: RecipeChatProposal(
                    versionLabel: "No-pork version",
                    ingredients: ["120 g beef bacon", "2 tbsp olive oil", "300 g pasta"],
                    steps: [
                        "Render the beef bacon in a dry pan until the edges crisp.",
                        "Toss the drained pasta through the fat and serve.",
                    ],
                    changes: [
                        "Prosciutto becomes beef bacon",
                        "Rendered a minute longer, because beef bacon carries less fat",
                    ],
                    summary: "The same dish without pork.",
                    servings: 4
                ),
                family: family,
                in: context
            )
        }
    }
}
