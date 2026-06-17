import CoreGraphics
import Observation

/// One frame of the interactive import walkthrough: a screenshot plus the
/// normalized location of the button the user must tap to advance.
struct TutorialStep: Identifiable {
    enum Pointer { case up, down }

    let id: Int
    let imageName: String
    let headline: String
    /// Normalized rect (0…1) relative to the displayed screenshot, origin top-left.
    let hotspot: CGRect
    let pointer: Pointer
    /// Frame 0 has no baked-in pill, so it draws its own "Tap here" label.
    let showsLabel: Bool
}

/// Pure, SwiftUI-free state machine for the import tutorial. Drives the
/// walkthrough → importing → success → cta progression. No real import happens.
@Observable
final class TutorialFlowModel {

    enum Phase: Equatable {
        case walkthrough(Int)
        case importing
        case success
        case cta
    }

    let steps: [TutorialStep]
    private(set) var phase: Phase = .walkthrough(0)
    /// Incremented on a wrong tap so the view can fire a one-shot "nudge" pulse.
    private(set) var nudgeToken = 0

    init(steps: [TutorialStep] = TutorialFlowModel.defaultSteps) {
        self.steps = steps
    }

    var currentStep: TutorialStep? {
        if case let .walkthrough(i) = phase, steps.indices.contains(i) { return steps[i] }
        return nil
    }

    var headline: String {
        switch phase {
        case let .walkthrough(i): return steps[i].headline
        case .importing:          return "Pulling out the recipe\u{2026}"
        case .success, .cta:      return "That's it \u{2014} it's saved. \u{2728}"
        }
    }

    /// User tapped the highlighted hotspot — advance.
    func tapHotspot() { advance() }

    /// Idle timeout elapsed — advance anyway (safety net so no one gets stuck).
    func idleFired() { advance() }

    /// User tapped outside the hotspot — nudge the mark, do not advance.
    func tapMiss() { nudgeToken += 1 }

    private func advance() {
        switch phase {
        case let .walkthrough(i):
            let next = i + 1
            phase = steps.indices.contains(next) ? .walkthrough(next) : .importing
        case .importing: phase = .success
        case .success:   phase = .cta
        case .cta:       break // terminal — CTA buttons own the exit
        }
    }
}

extension TutorialFlowModel {
    /// Hotspot rects are first guesses; tune them live in the simulator using
    /// the DEBUG tap-coordinate print in `WalkthroughFrame` (see Task 5).
    static let defaultSteps: [TutorialStep] = [
        TutorialStep(
            id: 0,
            imageName: "tutorialPost",
            headline: "Found a recipe you love?",
            hotspot: CGRect(x: 0.78, y: 0.92, width: 0.18, height: 0.05),
            pointer: .up,
            showsLabel: true
        ),
        TutorialStep(
            id: 1,
            imageName: "tutorialShareSheetApp",
            headline: "Just tap Share \u{2192} Glutt",
            hotspot: CGRect(x: 0.26, y: 0.85, width: 0.22, height: 0.08),
            pointer: .down,
            showsLabel: false
        ),
        TutorialStep(
            id: 2,
            imageName: "tutorialShareSheetSystem",
            headline: "Just tap Share \u{2192} Glutt",
            hotspot: CGRect(x: 0.27, y: 0.55, width: 0.18, height: 0.11),
            pointer: .up,
            showsLabel: false
        ),
    ]
}
