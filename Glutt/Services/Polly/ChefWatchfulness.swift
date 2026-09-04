import Foundation

/// How much Chef interferes when she can see what the cook is doing.
///
/// Only meaningful with a wearable camera. The phone camera is off by default and
/// lives on the counter pointing at the ceiling, so a promise to watch
/// continuously is one it cannot keep; the picker is hidden without them.
///
/// Three levels rather than a slider because the difference cooks care about is
/// not "how often" but "what counts as worth interrupting me for", and that is a
/// judgement, not a frequency. Frequency follows from it: a chef holding you to
/// the recipe exactly has to look more often than one waiting for you to ruin
/// something.
///
/// An enum, unlike its neighbour `PollyChefVoice`, because the prompt builder
/// and the watcher both need to handle every level and a missed case there is a
/// silent behaviour bug rather than a missing menu entry.
enum ChefWatchfulness: String, CaseIterable, Identifiable, Sendable {
    /// Holds the cook to the recipe. Cut sizes, order, technique, anything that
    /// is not what the recipe asked for.
    case perfectionist
    /// Stays out of the way until something is actually going to hurt the dish.
    case watchful
    /// Never volunteers. Answers when asked and looks when asked, which is the
    /// behaviour every cook had before this existed.
    case handsOff

    var id: String { rawValue }

    static let `default` = ChefWatchfulness.watchful

    var displayName: String {
        switch self {
        case .perfectionist: "Perfectionist"
        case .watchful: "Watchful"
        case .handsOff: "Hands off"
        }
    }

    /// One line under the name in the picker. Written so the difference is
    /// obvious at a glance, because this is chosen in the few seconds before a
    /// cook starts and nobody reads a paragraph there.
    var tagline: String {
        switch self {
        case .perfectionist: "Everything by the book, technique included"
        case .watchful: "Speaks up only if it'll hurt the dish"
        case .handsOff: "Looks only when you ask"
        }
    }

    /// Seconds between unprompted glances, or nil to never look unasked.
    ///
    /// Not tuned against anything yet, and deliberately not fast. The stream
    /// runs at 7 fps and a glance could in principle be every frame, but the
    /// limit is not the camera: it is that a cook who is told something every
    /// few seconds stops listening. Twelve seconds is roughly the pace of
    /// someone watching over your shoulder who mostly approves.
    var glanceInterval: TimeInterval? {
        switch self {
        case .perfectionist: 12
        case .watchful: 25
        case .handsOff: nil
        }
    }

    var watchesUnprompted: Bool { glanceInterval != nil }

    /// How many unprompted looks one step is allowed to spend.
    ///
    /// The interval alone is not a limit. A six minute reduction at twelve
    /// second intervals is thirty looks at a pan that is doing exactly one
    /// thing, and a cook who hears about it thirty times mutes her and never
    /// unmutes her. The budget is what turns "how often she looks" into "how
    /// much she is willing to say about one step", which is the thing the level
    /// names actually promise.
    ///
    /// Deliberately small. Most looks end in silence anyway, so a budget of two
    /// is not two remarks, it is at most two, and usually none.
    var glanceBudgetPerStep: Int {
        switch self {
        case .perfectionist: 3
        case .watchful: 2
        case .handsOff: 0
        }
    }

    /// The cook's choice, persisted across cooks.
    ///
    /// Read once at session start. Changing it mid-cook would mean rewriting the
    /// live prompt, which is possible but means Chef's manner changes in the
    /// middle of a sentence, so the picker sits on the pre-cook screen next to
    /// the chef picker for the same reason that one does.
    static var selectedID: String {
        get { UserDefaults.standard.string(forKey: selectionKey) ?? Self.default.rawValue }
        set { UserDefaults.standard.set(newValue, forKey: selectionKey) }
    }

    static var selected: ChefWatchfulness { named(selectedID) }

    /// Falls back rather than trapping. A level removed in a later version would
    /// otherwise crash every cook for anyone who had it selected.
    static func named(_ id: String?) -> ChefWatchfulness {
        guard let id, let level = ChefWatchfulness(rawValue: id) else { return .default }
        return level
    }

    private static let selectionKey = "glutt.polly.watchfulness"
}
