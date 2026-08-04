import Foundation

/// A chef the cook can pick before starting: who the chef voice sounds like, and
/// how it talks.
///
/// Three separate things travel together here because they have to stay in
/// sync. Shipping a voice without its speech style gives you Gordon Ramsay's
/// voice reading the house script, which lands worse than either on its own.
///
/// - `realtimeVoice` is the OpenAI Realtime voice when there is no clone
///   (Polly), and the mint still carries it as a fallback label.
/// - `elevenLabsVoiceID` when set (Gordon) means BOTH the briefing AND the live
///   cook use ElevenLabs: the session is minted `textOnly`, remote WebRTC audio
///   is muted, and `PollyVoicePlayer` speaks the model's words. `nil` = OpenAI
///   speech-to-speech for the live cook.
/// - `personaOverlay` is appended to the prompt and works on any voice.
struct PollyChefVoice: Identifiable, Equatable, Hashable, Sendable {
    /// Stable key. Persisted, so never renamed.
    let id: String
    let displayName: String
    /// One line under the name in the picker.
    let tagline: String
    /// OpenAI Realtime voice. Used for live audio when `elevenLabsVoiceID` is
    /// nil; otherwise the mint still asks for it but output is text-only.
    /// `marin` / `cedar` are the two OpenAI recommends for quality.
    let realtimeVoice: String
    /// ElevenLabs clone for briefing + live cook. `nil` = OpenAI voices only.
    let elevenLabsVoiceID: String?
    /// Appended to the prompt. Empty means house Polly, unmodified.
    let personaOverlay: String
    /// Style direction for the briefing's TTS call.
    let briefingStyle: String

    static let `default` = Self.polly

    static let all: [PollyChefVoice] = [.polly, .gordonRamsay]

    static func named(_ id: String?) -> PollyChefVoice {
        all.first { $0.id == id } ?? .default
    }

    /// The cook's choice, persisted across sessions.
    ///
    /// Read at session start and never mid-cook: the Realtime API only accepts a
    /// `voice` change while no audio has been output yet, so switching chefs
    /// during a conversation is not something the platform allows at all. The
    /// picker lives on the pre-cook screen for that reason, not as a style
    /// preference.
    static var selectedID: String {
        get { UserDefaults.standard.string(forKey: selectionKey) ?? Self.default.id }
        set { UserDefaults.standard.set(newValue, forKey: selectionKey) }
    }

    static var selected: PollyChefVoice { named(selectedID) }

    private static let selectionKey = "glutt.polly.chefVoice"

    // MARK: - Catalog

    /// The house voice. `id` stays "polly" because it is the persisted selection
    /// key; only the name the cook reads changed.
    static let polly = PollyChefVoice(
        id: "polly",
        displayName: "Chef",
        tagline: "Calm, expert, always beside you",
        realtimeVoice: "marin",
        elevenLabsVoiceID: nil,
        personaOverlay: "",
        briefingStyle: "Speak like a warm chef giving a quick pre-cook rundown. Brisk and clear, not slow, not chirpy."
    )

    static let gordonRamsay = PollyChefVoice(
        id: "gordon-ramsay",
        displayName: "Gordon Ramsay",
        tagline: "Exacting, generous with praise, allergic to waste",
        // Cedar remains the mint fallback; live audio is the ElevenLabs clone
        // via text-only output (see PollySessionController.start).
        realtimeVoice: "cedar",
        elevenLabsVoiceID: "5i0YBih50ehVs4WoAmac",
        personaOverlay: Self.ramsayOverlay,
        briefingStyle: "Speak like an exacting British chef running through the plan before service. Warm, quick, precise. Land the praise, do not linger."
    )

    /// Deliberately the MasterClass register, not the Hell's Kitchen one.
    ///
    /// The televised persona is abusive and built for conflict; the teaching
    /// persona is described as quiet, nurturing, succinct, and eager for you to
    /// succeed. Someone holding a hot pan needs the second one, and it is also
    /// the only one that does not fight Polly's own "be directional, never
    /// chatty" rules.
    private static let ramsayOverlay = """

    # Your voice this session: Gordon Ramsay
    You are cooking as Gordon Ramsay in teaching mode: the MasterClass kitchen,
    not the television one. Exacting, fast, and genuinely on the cook's side.
    Everything in the sections above still applies, this only changes HOW you say
    it. When this conflicts with a rule above, the rule above wins.

    ## How he sounds
    - Short, declarative, physical. Verb first: "Get that pan screaming hot."
      "Season it. Both sides. Properly."
    - Praise is frequent, specific and immediate. "Beautiful." "Stunning." "That
      is exactly it." Never generic, never more than a few words, and only when
      something has actually been done well.
    - Repeat a word for emphasis rather than adding sentences: "Nice and slow.
      Slow." "Look at that. Look at it."
    - British kitchen idiom: "colour on it", "give it a minute", "right", "lovely
      bit of", "a touch of", "hot pan, cold oil". Say "chopping board" not
      "cutting board", "coriander" not "cilantro", "aubergine" not "eggplant",
      "prawns" not "shrimp".
    - Mark a win with the praise alone — "Beautiful." "That is exactly it." Never
      the word "chef": that is what the cook says to wake you.

    ## What he cares about, in this order
    1. Heat. Pan hot before anything touches it, and residual heat finishes the
       job after the hob is off.
    2. Seasoning, early and in layers, then tasted. "Taste it. Now tell me."
    3. Keep it moving. Nothing sits still and nothing gets crowded.
    4. Butter and fat as finishing, basting, emulsifying.
    5. Waste. Stalks, bones, fat, herb stems all have a use.

    ## Rescue
    Something splits, catches, or breaks and he gets QUIETER and faster, never
    louder. Name it, give the fix in one move, move on. "Right, it has split. Off
    the heat. Splash of cold water, whisk hard. Keep going."

    ## Hard limits
    - Never swear and never insult the cook or their food. The abuse is
      television; this is teaching. If something is wrong, say what to do about
      it instead.
    - No catchphrase cosplay. Never say "where's the lamb sauce", never call
      anyone a donkey, never reference raw or idiot sandwiches. One quotation
      breaks the whole thing.
    - Praise has a budget: at most one "beautiful" or "stunning" every few turns.
      Constant praise is worth nothing.
    - Never claim to be the real person, never refer to his restaurants,
      television programmes, family or awards. You are a cooking voice, and if
      asked directly, say plainly that you are Glutt's chef voice.
    """
}
