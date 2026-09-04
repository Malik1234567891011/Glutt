import AVFoundation
import Foundation

/// The sound that says "I'm listening".
///
/// Built after watching somebody cook. They said "Chef", could not tell whether
/// it had landed, and walked back to the counter to look at the phone. The only
/// feedback the session gave was a pill and a glowing edge on a screen they were
/// not looking at, and a cook has their hands in a bowl and their back turned.
///
/// # Why it is not two beeps
///
/// The first version was two sine blips, and it sounded like a microwave. That
/// is not a matter of taste: a pure sine is the timbre of a piezo buzzer and a
/// dev-kit default, and the sound design literature is blunt that generic
/// earcons sound generic *because* they are signal-generated sine or square
/// tones. Premium ones are layered, use real harmonic structure, and imply
/// actual musical harmony. In one study, interfaces with crafted sounds
/// outperformed the same interfaces with generic sounds by about a third.
///
/// So this synthesises a struck wooden bar, and three things do the work:
///
/// **Partials, not a sine.** A marimba bar is tuned so its overtones land at
/// four and ten times the fundamental, which is where its hollow, woody colour
/// comes from. An octave partial is added underneath for body and a quiet
/// inharmonic one on top for air.
///
/// **Frequency-dependent decay.** In every struck object the high partials die
/// away faster than the low ones. This is the single detail that separates a
/// struck thing from a synthesised one, and it costs one multiplication.
///
/// **Two notes that overlap.** The second note arrives while the first is still
/// ringing, so a rising fifth is heard as a chord rather than as two separate
/// events. It stops being two beeps and starts being one gesture, which is the
/// whole difference between a noise and a sound somebody would recognise.
///
/// Warm, clean, and not a generic AI bleep, which is the brand written down.
///
/// Generated rather than shipped as an asset: nothing to lose from a bundle,
/// and every choice here is a number somebody can argue with. Rendered once and
/// kept, because it plays constantly.
@MainActor
enum ListeningEarcon {

    // MARK: - The composition

    /// A rising perfect fifth, A4 to E5.
    ///
    /// The fifth is the most consonant interval after the octave, which matters
    /// far more than it would for a sound heard once: this plays every time the
    /// cook speaks, perhaps thirty times in a session, and anything with tension
    /// in it becomes unbearable at that rate. Rising, because a falling pair
    /// reads as dismissal or error, and this is the opposite message.
    ///
    /// A fourth below where this started, chosen by ear against the others. The
    /// higher versions were brighter and read as a device announcing itself;
    /// down here it reads as something in the room. Low enough to be warm and
    /// still above the extractor fan and the pan, which is where a kitchen puts
    /// its noise.
    private static let notes: [(frequency: Double, startsAt: Double, level: Float)] = [
        (440.00, 0.000, 1.00),   // A4
        (659.25, 0.090, 0.92),   // E5, landing while A4 still rings
    ]

    /// How long the whole thing lasts, tail included.
    ///
    /// Long enough to ring rather than click, short enough to be over before it
    /// could interrupt anybody. Slightly longer than the brighter versions
    /// needed: a lower fundamental wants more room to bloom before it is cut
    /// off, and clipping the tail is what makes a warm sound read as a thud.
    private static let duration: Double = 0.70

    /// Overall level. Quiet: it plays over an extractor fan and it plays often,
    /// and an assertive noise thirty times a cook is worse than no noise at all.
    private static let amplitude: Float = 0.30

    /// How fast the whole thing dies away.
    ///
    /// Gentler than the brighter versions used. Warmth is largely a matter of
    /// letting the low partials ring, and a fast decay on a low fundamental
    /// just sounds like a knock.
    private static let decayRate: Double = 2.8

    /// The overtones of a struck wooden bar, as multiples of the fundamental.
    ///
    /// 4 and 10 are the real marimba intervals, tuned into the instrument by the
    /// arch cut into the underside of each bar. 2 adds body underneath them, and
    /// the slightly-off 9.2 is air rather than pitch: deliberately not a whole
    /// number, because exact integers ring like an organ and struck objects do
    /// not.
    private static let partials: [(ratio: Double, level: Float, decay: Double)] = [
        (1.0,  1.00, 1.00),
        (2.0,  0.30, 1.35),
        (4.0,  0.18, 2.10),
        (9.2,  0.06, 3.40),
    ]

    // MARK: - Playing

    private static var player: AVAudioPlayer?
    private static var rendered: Data?

    /// Play it, unless it is already playing.
    ///
    /// Never throws and never disturbs the session. A missing earcon is a
    /// missing courtesy; a broken cook session is somebody standing over a pan
    /// with no help.
    static func play() {
        guard player?.isPlaying != true else { return }
        do {
            let data = try rendered ?? wav()
            rendered = data
            let sound = try AVAudioPlayer(data: data)
            sound.volume = 1
            // Rides the session the cook session already configured, so it
            // follows the route: through the headset when one is on, the
            // speaker when not.
            sound.prepareToPlay()
            sound.play()
            player = sound
        } catch {
            PollyDebugLog.shared.log("earcon: could not play — \(error.localizedDescription)")
        }
    }

    // MARK: - Synthesis

    private static let sampleRate: Double = 44_100

    /// Render both notes into one buffer, summed where they overlap.
    static func samples() -> [Float] {
        var buffer = [Float](repeating: 0, count: Int(sampleRate * duration))

        for note in notes {
            let offset = Int(note.startsAt * sampleRate)
            let remaining = buffer.count - offset
            guard remaining > 0 else { continue }

            for index in 0..<remaining {
                let seconds = Double(index) / sampleRate
                var value: Float = 0

                for partial in partials {
                    let frequency = note.frequency * partial.ratio
                    // Nothing above hearing, and nothing that would alias.
                    guard frequency < sampleRate / 2 else { continue }
                    // Exponential decay, faster the higher the partial sits.
                    // This is the line that makes it a struck object.
                    let decay = Float(exp(-seconds * decayRate * partial.decay))
                    let phase = 2 * Double.pi * frequency * seconds
                    value += Float(sin(phase)) * partial.level * decay
                }

                // A short soft attack. A struck bar is not instant, and a hard
                // edge on a sine is a click, which is exactly the small
                // ugliness that starts to grate on the twentieth hearing.
                let attack = min(1, Float(seconds / 0.006))
                buffer[offset + index] += value * note.level * attack
            }
        }

        // Normalise, then set the level here rather than hoping the sum landed
        // somewhere sensible. Summed partials and overlapping notes make the
        // peak hard to predict and easy to clip.
        let peak = buffer.map { abs($0) }.max() ?? 1
        guard peak > 0 else { return buffer }
        let scale = amplitude / peak
        return buffer.map { $0 * scale }
    }

    /// A minimal 16-bit mono PCM WAV, built in memory.
    private static func wav() throws -> Data {
        let rendered = samples()
        var data = Data()
        let bytes = rendered.count * 2

        func append(_ string: String) { data.append(contentsOf: Array(string.utf8)) }
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

        append("RIFF"); append32(UInt32(36 + bytes)); append("WAVE")
        append("fmt "); append32(16); append16(1); append16(1)
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate) * 2)
        append16(2); append16(16)
        append("data"); append32(UInt32(bytes))
        for sample in rendered {
            let clamped = max(-1, min(1, sample))
            withUnsafeBytes(of: Int16(clamped * Float(Int16.max)).littleEndian) {
                data.append(contentsOf: $0)
            }
        }
        return data
    }
}
