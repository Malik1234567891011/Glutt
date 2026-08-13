import SwiftUI

/// The visual language of the Pro tier.
///
/// The rule these are built to: **show, don't hide.** A free cook should see
/// every feature Glutt has, sitting exactly where it will sit once they pay,
/// wearing a crown. Nothing is removed from a screen for being locked, because a
/// feature you never see is a feature you never buy.
///
/// Colour: amber (`Theme.Colors.amber` on `amberChip`) rather than the herb
/// green. Green is the palette's *go* colour, on every primary button in the
/// app, so a green crown on a control that does not work would be a lie told in
/// colour. Amber already means "attention, not ready" here (low stock, use
/// soon), and gold is the universal read for premium.
///
/// The glyph is SF Symbols' `crown.fill`, matching the app's existing habit of
/// mixing SF Symbols in with Phosphor and Material Symbols. Swapping it for a
/// drawn Phosphor asset later is a change to `PremiumCrown` alone.

// MARK: - The crown

struct PremiumCrown: View {
    enum Style {
        /// Sits inside a label or on a control's corner.
        case inline
        /// A standalone badge on its own disc, for corners of large surfaces.
        case disc
    }

    var style: Style = .inline

    var body: some View {
        switch style {
        case .inline:
            crown(14)
        case .disc:
            crown(15)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Theme.Colors.amberChip))
                .overlay(Circle().strokeBorder(Theme.Colors.amber.opacity(0.28), lineWidth: 1))
                .shadow(color: Theme.Colors.textPrimary.opacity(0.10), radius: 6, y: 2)
        }
    }

    private func crown(_ size: CGFloat) -> some View {
        Image(systemName: "crown.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Theme.Colors.amber)
            // The parent control owns the label; a second one would have
            // VoiceOver read "crown" after every button title in the app.
            .accessibilityHidden(true)
    }
}

// MARK: - Gating any control

/// Draws the crown on a control that is behind the paywall. **Badge only.** The
/// control keeps its own gesture, and its *action* is what gets gated, by
/// routing it through `Entitlements.perform`:
///
/// ```swift
/// Button { gate.perform(.cookWithChef) { startCooking() } } label: { … }
///     .premiumCrown(.cookWithChef)
/// ```
///
/// It used to try to be cleverer than that — wrap the control, switch off its
/// hit testing, and catch the tap from outside — so a call site needed one
/// modifier and no thought. Two variants of that were built and both silently
/// swallowed the tap: no action, no paywall, no error, nothing in the log. The
/// second one even produced a Button with no hittable region at all, because its
/// entire label was the control that had just been disabled. Splitting the badge
/// from the gate costs one extra line per call site and cannot fail that way,
/// which is the better trade for something that sits between a user and paying.
///
/// The control keeps its normal appearance rather than being dimmed or disabled.
/// A greyed-out button reads as "broken" or "not applicable here"; a live
/// looking button wearing a crown reads as "this is for members", which is the
/// message that sells.
private struct PremiumCrownBadge: ViewModifier {
    let feature: PremiumFeature
    let alignment: Alignment
    /// Nudges the crown off the content's corner, for controls whose visual edge
    /// is inset from their frame.
    let offset: CGSize

    /// Nil only where the environment was never injected, which is previews.
    /// Defaults to **free**, deliberately: a screen that forgets the injection
    /// then shows crowns everywhere, which is noticed in seconds. Defaulting the
    /// other way would silently hand out the paid features instead.
    @Environment(Entitlements.self) private var gate: Entitlements?

    func body(content: Content) -> some View {
        if gate.isPro {
            content
        } else {
            content
                .overlay(alignment: alignment) {
                    PremiumCrown(style: .disc)
                        .offset(offset)
                        // The badge is decoration over a control that already
                        // handles the tap; catching taps here would put a dead
                        // zone over the middle of the thing we want tapped.
                        .allowsHitTesting(false)
                }
                .accessibilityHint("\(feature.title) is part of Glutt \(PremiumFeature.tierName). Opens the plans.")
        }
    }
}

extension View {
    /// Marks this control as Pro. Draws the crown only; gate the control's
    /// action with `gate.perform(_:action:)`.
    func premiumCrown(
        _ feature: PremiumFeature,
        alignment: Alignment = .topTrailing,
        offset: CGSize = CGSize(width: 8, height: -8)
    ) -> some View {
        modifier(PremiumCrownBadge(feature: feature, alignment: alignment, offset: offset))
    }
}

// MARK: - Menu rows

/// A menu row's label, carrying an inline crown when the feature is locked.
///
/// Menus can't take an overlay: a `Button` inside `Menu { }` is rendered by
/// UIKit from its `Label`, so the crown has to be part of the title itself.
struct PremiumMenuLabel: View {
    let title: String
    let systemImage: String
    let feature: PremiumFeature
    var isPro: Bool

    var body: some View {
        if isPro {
            Label(title, systemImage: systemImage)
        } else {
            Label {
                // Interpolating the symbol keeps it on the text baseline and
                // inside the title, which is the only place a menu will draw it.
                Text("\(title) \(Image(systemName: "crown.fill"))")
            } icon: {
                Image(systemName: systemImage)
            }
        }
    }
}

// MARK: - Inline notice

/// The banner that sits where a locked feature's content would be, saying what
/// it is and how to get it. The equivalent of ReciMe's yellow nutrition strip.
struct PremiumNoticeBanner: View {
    let feature: PremiumFeature
    var message: String?

    @Environment(Entitlements.self) private var gate: Entitlements?

    var body: some View {
        Button {
            Haptics.impact(.light)
            gate?.presentPaywall(for: feature)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                PremiumCrown()
                    .padding(.top, 1)
                Text(message ?? "\(feature.title) is part of Glutt \(PremiumFeature.tierName). Subscribe to unlock it.")
                    .font(BrandFont.nunito(13.5, 700))
                    .foregroundStyle(Color(hex: 0x6B5518))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.amberChip)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous)
                    .strokeBorder(Theme.Colors.amber.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Whole-surface lock

/// Covers a whole surface (a tab, a deck) with a blur, leaving the shape and
/// colour of what's underneath readable so the cook can see there is something
/// there worth having.
struct PremiumSurfaceLock: View {
    let feature: PremiumFeature
    let headline: String
    let message: String
    /// Extra bottom padding, so the CTA clears the floating tab bar.
    var bottomInset: CGFloat = 0

    @Environment(Entitlements.self) private var gate: Entitlements?

    var body: some View {
        ZStack {
            // Warm scrim rather than a grey one: this sits over cream, and a
            // neutral veil turns the whole palette cold.
            Theme.Colors.background.opacity(0.72)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                PremiumCrown(style: .disc)
                    .scaleEffect(1.35)

                Text(headline)
                    .font(BrandFont.bricolage(23, 700))
                    .foregroundStyle(Theme.Colors.heading)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(BrandFont.nunito(14.5, 600))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 290)

                Button {
                    Haptics.impact(.medium)
                    gate?.presentPaywall(for: feature)
                } label: {
                    Text("See plans")
                        .font(BrandFont.nunito(16, 800))
                        .foregroundStyle(Theme.Colors.creamText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Capsule().fill(Theme.Colors.accent))
                        .shadow(color: Theme.Colors.textPrimary.opacity(0.14), radius: 16, y: 8)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .frame(maxWidth: 300)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, bottomInset)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(headline). \(message)")
    }
}

extension View {
    /// Blurs this surface and drops a `PremiumSurfaceLock` over it for free
    /// cooks. What's underneath stays visible as shape and colour, never as
    /// readable content.
    func premiumLockedSurface(
        _ feature: PremiumFeature,
        isUnlocked: Bool,
        headline: String,
        message: String,
        bottomInset: CGFloat = 0
    ) -> some View {
        ZStack {
            self
                .blur(radius: isUnlocked ? 0 : 9)
                .allowsHitTesting(isUnlocked)
                // Blur samples past the edges; overfill so soft borders never
                // show at the surface's rim.
                .scaleEffect(isUnlocked ? 1 : 1.04)
                .clipped()
            if !isUnlocked {
                PremiumSurfaceLock(
                    feature: feature,
                    headline: headline,
                    message: message,
                    bottomInset: bottomInset
                )
            }
        }
    }
}

// There is deliberately no "N swipes left" component here. The Discover meter is
// silent until it runs out: a visible counter makes people ration the deck and
// weigh every card against the number, which is the opposite of what a browse
// feed is for. See `PlatesTabView`.

#Preview("Crowned control") {
    VStack(spacing: 28) {
        PremiumCrown()
        PremiumCrown(style: .disc)

        Button("Cook with Chef") {}
            .font(BrandFont.nunito(16.5, 800))
            .foregroundStyle(Theme.Colors.creamText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Capsule().fill(Theme.Colors.accent))
            .premiumCrown(.cookWithChef)

        PremiumNoticeBanner(feature: .recipeExtras)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.Colors.background)
}
