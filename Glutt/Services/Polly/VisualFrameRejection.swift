// Extracted from the deleted `VisualFrameGate.swift` when the Meta glasses code
// was removed (see docs/glasses-removal.md).
//
// The gate itself measured blur, brightness and duplicate frames, and only the
// glasses camera ever fed it. This type is different: it is the vocabulary the
// tool layer uses to explain a failed look to Chef, and the phone camera raises
// it too (`PollyVisualCapture` returns `.noFrames` when a phone capture comes
// back empty). So the measurement went and the vocabulary stayed.
//
// `warmingUp` and `feedStopped` describe glasses behaviour and are currently
// unreachable. They are kept deliberately: they cost nothing, they document
// what the cases meant, and restoring the glasses restores their meaning.

import Foundation

/// Why a frame is not worth showing Polly. Carried all the way out to the tool
/// result so she can say "hold still for a second" instead of guessing at a
/// smear, or asking about a pan she cannot actually see.
enum VisualFrameRejection: String, Sendable, Error {
    case noFrames = "no_frames"
    case tooOld = "frame_too_old"
    case blurred = "frame_blurred"
    case tooDark = "frame_too_dark"
    case tooBright = "frame_too_bright"
    /// The glasses camera is on its way up and has not delivered a frame yet.
    ///
    /// Its own case because it is the one failure that fixes itself. A cook who
    /// asks "does this look right" before the first frame arrives used to hear
    /// "no picture is coming through, check the camera" — advice for a problem
    /// they do not have, about a camera that is working. Chef needs to say she
    /// is nearly there and answer from what she already knows.
    ///
    /// The window is about two seconds over Bluetooth. It was 14 to 20 on the
    /// Wi-Fi transport, which is why this case exists at all.
    case warmingUp = "camera_warming_up"
    /// The feed was running and has stopped, rather than the picture being old
    /// because the cook moved.
    ///
    /// `tooOld` tells them to look at what they are working on, which is the
    /// right advice when a head turn left the buffer behind and useless advice
    /// when nothing has arrived over the radio for a minute. In a real cook Chef
    /// said "point it at the cutting board and hold still" three times at a cook
    /// who was already pointing at the cutting board and holding still.
    case feedStopped = "camera_feed_stopped"

    /// What Polly should ask the cook to do about it. Kept here so the wording
    /// lives next to the condition that produced it.
    var suggestion: String {
        switch self {
        case .noFrames:
            return "No picture is coming through. Ask the cook to check the camera."
        case .tooOld:
            return "The view has gone stale. Ask the cook to look at what they are working on."
        case .blurred:
            return "Everything is smeared with movement. Ask the cook to hold still for a second."
        case .tooDark:
            return "It is too dark to judge. Ask the cook to turn a light on or move closer."
        case .tooBright:
            return "The picture is blown out. Ask the cook to angle away from the light."
        case .feedStopped:
            return "The picture has stopped arriving from the glasses. This is not something "
                + "the cook can fix by moving or holding still, so do not ask them to. Say you "
                + "have lost the view, keep going on what they tell you, and mention it may "
                + "come back on its own."
        case .warmingUp:
            // Phrased as what to do rather than what to avoid. The first version
            // ended "do not ask them to check the camera", which is the exact
            // instruction a model is most likely to invert, and it put the
            // wrong phrase in front of it at the same time.
            return "Your eyes are still connecting, which takes a couple of seconds. Say so "
                + "in your own words, answer from the recipe and what they have told you, and "
                + "offer to look properly in a moment. Nothing is wrong on their end."
        }
    }
}
