import Foundation
import SwiftData

/// Reads and writes the local, unsynced chat thread for a recipe family.
///
/// The thread is disposable by design: it lives only on this phone, it is
/// capped, and losing it costs the cook nothing but a re-ask.
enum RecipeChatStore {

    /// How many turns are kept on disk. Past this the oldest go.
    static let historyCap = 30

    /// How many of those turns are replayed to the model. Far smaller than the
    /// cap because every turn re-sends the whole recipe context alongside it —
    /// this is the dial that decides what a long conversation costs.
    static let contextTurns = 8

    // MARK: - Identity

    /// The conversation is keyed to the original recipe, so every version of a
    /// dish shares one thread.
    ///
    /// `remoteID` is backfilled at launch (`RootView`), so it is present in
    /// practice; the title/creator fallback covers the window before that and
    /// costs nothing. Neither is written here — opening a chat must not dirty a
    /// recipe and trigger a sync push.
    static func familyKey(for recipe: Recipe) -> String {
        let family = recipe.parentRecipe ?? recipe
        if let id = family.remoteID {
            return id.uuidString
        }
        return "local:" + RecipeIdentity.matchKey(title: family.title, creator: family.sourceCreator)
    }

    // MARK: - Reads

    static func messages(family: String, in context: ModelContext) -> [RecipeChatMessage] {
        var descriptor = FetchDescriptor<RecipeChatMessage>(
            predicate: #Predicate { $0.familyKey == family },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        descriptor.fetchLimit = historyCap
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Writes

    @discardableResult
    static func append(
        role: RecipeChatRole,
        text: String,
        proposal: RecipeChatProposal? = nil,
        family: String,
        in context: ModelContext
    ) -> RecipeChatMessage {
        let encoded = proposal.flatMap { proposal -> String? in
            guard let data = try? JSONEncoder().encode(proposal) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        let message = RecipeChatMessage(role: role, text: text, familyKey: family, proposalJSON: encoded)
        // Two turns can land in the same tick — the pantry chip writes the
        // question and its answer together, with no network hop between them.
        // Nudging keeps the sort total, so they can't render out of order.
        if let last = messages(family: family, in: context).last, last.createdAt >= message.createdAt {
            message.createdAt = last.createdAt.addingTimeInterval(0.001)
        }
        context.insert(message)
        trim(family: family, in: context)
        return message
    }

    static func clear(family: String, in context: ModelContext) {
        for message in messages(family: family, in: context) {
            context.delete(message)
        }
    }

    /// Drops the oldest turns past the cap. Runs on every append, so the thread
    /// can only ever be one message over.
    private static func trim(family: String, in context: ModelContext) {
        let descriptor = FetchDescriptor<RecipeChatMessage>(
            predicate: #Predicate { $0.familyKey == family },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        guard let all = try? context.fetch(descriptor), all.count > historyCap else { return }
        for message in all.prefix(all.count - historyCap) {
            context.delete(message)
        }
    }
}

extension RecipeChatMessage {
    /// The proposal carried by this turn, if it carried one.
    var proposal: RecipeChatProposal? {
        guard let json = proposalJSON, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(RecipeChatProposal.self, from: data)
    }
}
