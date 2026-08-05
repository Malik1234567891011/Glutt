import Foundation
import SwiftData

enum RecipeChatRole: String, Codable {
    case user
    case assistant
}

/// One turn of a recipe's chat with Polly.
///
/// Deliberately not a relationship on `Recipe`: the sync encoder walks that
/// model, and a local chat log is not worth widening the sync body for. The
/// link is a plain string key instead (`RecipeChatStore.familyKey`), which also
/// keeps this model entirely absent from anything the server ever sees.
///
/// The key is the *family* — the original recipe, not the version — so applying
/// a change and landing on the new version continues the same conversation
/// rather than opening an empty one.
@Model
final class RecipeChatMessage {
    /// `RecipeChatRole.rawValue`, stored raw so a value written by a future app
    /// version still loads (the computed `role` falls back).
    var roleRaw: String
    var text: String
    var createdAt: Date
    var familyKey: String

    /// The proposed rewrite, JSON-encoded. Nil when the turn was just an answer,
    /// which is the common case — most questions don't change the recipe.
    var proposalJSON: String?

    /// The version label, set once the cook tapped Apply. Turns the card from an
    /// offer into a receipt, so re-opening the thread can't mint a duplicate
    /// version from the same proposal.
    var appliedLabel: String?

    init(role: RecipeChatRole, text: String, familyKey: String, proposalJSON: String? = nil) {
        self.roleRaw = role.rawValue
        self.text = text
        self.createdAt = .now
        self.familyKey = familyKey
        self.proposalJSON = proposalJSON
    }

    var role: RecipeChatRole { RecipeChatRole(rawValue: roleRaw) ?? .assistant }
}
