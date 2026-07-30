import SwiftUI

/// "The card grows into the screen" push, the way Airbnb opens a listing: the
/// card you tapped scales up into the full detail screen while the two
/// cross-fade, and dragging back down shrinks it into the card it came from.
///
/// iOS 18 does this natively — `matchedTransitionSource` on the card pairs with
/// `navigationTransition(.zoom(…))` on the destination, which also buys the
/// interactive drag-to-shrink dismissal. On iOS 17 every modifier here is a
/// no-op and the push slides in as it always did.
///
/// Two things make this need more than one modifier per side. A screen can show
/// the same recipe twice — the "ready to cook tonight" hero is also a row in the
/// list below — and two sources sharing an id in one namespace is ambiguous, so
/// ids name the *card*, not the recipe, and `ZoomSource` remembers which card
/// the finger landed on. And pushes with no card behind them (deep links, launch
/// hooks, the share extension) must not grow out of a stale card, so those fall
/// back to a plain slide.

// MARK: - Identity

/// One card on screen: the model it shows, plus the slot it sits in. The slot is
/// what keeps the hero and its duplicate row in the list below apart.
struct ZoomCardID: Hashable {
    let model: AnyHashable
    let slot: String

    init(_ model: some Hashable, slot: String) {
        self.model = AnyHashable(model)
        self.slot = slot
    }
}

/// The card the next push should grow out of, recorded the moment the finger
/// goes down — always before the link activates, so the destination is built
/// knowing where it came from.
///
/// Deliberately not `@Observable`: pressing a card must not re-render the feed
/// that card lives in. The destination reads this when it is built, which is
/// after the press either way.
final class ZoomSource {
    var card: ZoomCardID?

    /// The card to grow out of for a screen showing `model` — nil when the push
    /// came from nowhere, or from a card showing something else.
    func card(for model: some Hashable) -> ZoomCardID? {
        guard let card, card.model == AnyHashable(model) else { return nil }
        return card
    }
}

// MARK: - Environment

private struct ZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

private struct ZoomSourceKey: EnvironmentKey {
    static let defaultValue: ZoomSource? = nil
}

extension EnvironmentValues {
    /// Namespace shared by one stack's zoom sources and destinations. Nil in
    /// stacks that never opted in, which makes the modifiers below no-ops.
    var zoomNamespace: Namespace.ID? {
        get { self[ZoomNamespaceKey.self] }
        set { self[ZoomNamespaceKey.self] = newValue }
    }

    var zoomSource: ZoomSource? {
        get { self[ZoomSourceKey.self] }
        set { self[ZoomSourceKey.self] = newValue }
    }
}

// MARK: - Modifiers

extension View {
    /// Hosts zoom transitions for a `NavigationStack`: hands the namespace and
    /// the pressed-card record to every card and destination inside it.
    func zoomTransitions(_ namespace: Namespace.ID, source: ZoomSource) -> some View {
        environment(\.zoomNamespace, namespace)
            .environment(\.zoomSource, source)
    }

    /// Marks a tappable card as the shape its push grows out of. Goes on the
    /// `NavigationLink` in place of `.buttonStyle(.plain)` — it draws the label
    /// exactly the same way, and catches the press on the way through.
    func zoomCard(_ id: ZoomCardID, cornerRadius: CGFloat = Theme.Radius.cardLarge) -> some View {
        modifier(ZoomCardModifier(id: id, cornerRadius: cornerRadius))
    }

    /// Grows this screen out of `card`. Pass nil for pushes that weren't started
    /// by a card, so they slide instead of zooming out of nothing.
    func zoomedFrom(_ card: ZoomCardID?) -> some View {
        modifier(ZoomDestinationModifier(card: card))
    }
}

private struct ZoomCardModifier: ViewModifier {
    let id: ZoomCardID
    let cornerRadius: CGFloat
    @Environment(\.zoomNamespace) private var namespace

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18, *), let namespace {
            content
                .buttonStyle(ZoomCardButtonStyle(id: id))
                .matchedTransitionSource(id: id, in: namespace) {
                    // Without this the zoom starts from a square, and the card's
                    // 26pt corners pop the moment you tap.
                    $0.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
        } else {
            content.buttonStyle(.plain)
        }
    }
}

private struct ZoomDestinationModifier: ViewModifier {
    let card: ZoomCardID?
    @Environment(\.zoomNamespace) private var namespace

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18, *), let namespace, let card {
            content.navigationTransition(.zoom(sourceID: card, in: namespace))
        } else {
            content
        }
    }
}

/// Draws the label untouched, like `.plain`, and records the press. Press state
/// flips on finger-down, so the source is always in place before the push.
private struct ZoomCardButtonStyle: ButtonStyle {
    let id: ZoomCardID

    func makeBody(configuration: Configuration) -> some View {
        PressRecorder(id: id, configuration: configuration)
    }

    /// A real view rather than a bare `configuration.label`, because button
    /// styles can't read `@Environment` themselves.
    private struct PressRecorder: View {
        let id: ZoomCardID
        let configuration: ButtonStyleConfiguration
        @Environment(\.zoomSource) private var source

        var body: some View {
            configuration.label
                .onChange(of: configuration.isPressed) { _, pressed in
                    if pressed { source?.card = id }
                }
        }
    }
}
