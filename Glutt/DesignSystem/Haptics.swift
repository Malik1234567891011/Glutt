import UIKit

/// App-wide haptic feedback. Thin wrappers over UIKit's feedback generators.
/// No-ops gracefully where haptics aren't available (e.g. Simulator produces nothing).
///
/// Usage:
///   Haptics.selection()        // tabs, segmented control, pickers, category/filter taps
///   Haptics.impact(.medium)    // buttons, toggles, steppers, primary CTAs
///   Haptics.notify(.success)   // outcomes — added to groceries, finished cooking, errors
enum Haptics {

    /// A light "selection moved" tick — for changing tab, segment, picker, or filter.
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
}
