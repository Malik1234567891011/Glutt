import UIKit

/// App-wide haptic feedback. Thin wrappers over UIKit's feedback generators.
/// No-ops gracefully where haptics aren't available (e.g. the Simulator produces nothing —
/// haptics can only be felt on a physical device).
///
/// Taxonomy — keep usage consistent:
///   selection()        → navigation / value change (tabs, segments, pickers, steppers, card taps)
///   impact(.light)     → secondary taps, toggles, dismissals
///   impact(.medium)    → primary commit (CTAs, confirming an action)
///   notify(.success/.warning/.error) → outcomes (added to groceries, finished cooking, errors)
///   celebrate()        → a meaningful, earned completion (finishing a cook)
enum Haptics {

    /// A light "selection moved" tick — for changing tab, segment, picker, stepper, or filter.
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }

    /// A physical tap — for buttons, checkbox toggles, steppers. Defaults to light.
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    /// An outcome cue — `.success`, `.warning`, or `.error`.
    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }

    /// A celebratory cue for an earned completion (e.g. finishing a cook):
    /// a firm tap immediately followed by a success notification.
    static func celebrate() {
        impact(.medium)
        notify(.success)
    }
}
