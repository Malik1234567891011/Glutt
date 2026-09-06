import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // Scales with the reader, capped at 24 so a full width button does
            // not become three lines tall. The vertical padding is fixed, so
            // the button grows with its label rather than clipping it.
            .font(BrandFont.bricolage(17, 600, relativeTo: .headline, maxSize: 24))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Theme.Colors.accent.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BrandFont.bricolage(17, 600, relativeTo: .headline, maxSize: 24))
            .multilineTextAlignment(.center)
            .foregroundStyle(Theme.Colors.accent)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .strokeBorder(Theme.Colors.accent, lineWidth: 1.5)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct PillButtonStyle: ButtonStyle {
    var tint: Color = Theme.Colors.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.gluttCaption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Filled capsule — the CTA on smart cards. Small but unmistakably tappable.
struct FilledPillButtonStyle: ButtonStyle {
    var tint: Color = Theme.Colors.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.gluttCaption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(tint.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var gluttPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var gluttSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var gluttPill: PillButtonStyle { PillButtonStyle() }
}

extension ButtonStyle where Self == FilledPillButtonStyle {
    static var gluttPillFilled: FilledPillButtonStyle { FilledPillButtonStyle() }
}
