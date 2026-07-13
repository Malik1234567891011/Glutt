import SwiftUI

/// The tutorial's phone-within-the-phone: 240×510 bezel; content is authored
/// at the design's 390×830 canvas and scaled by 240/390 (the HTML's trick).
struct MiniPhoneFrame<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .top) {
            content
                .frame(width: 390, height: 830)
                .scaleEffect(240.0 / 390.0, anchor: .topLeading)
                .frame(width: 240, height: 510, alignment: .topLeading)

            Capsule().fill(.black) // notch
                .frame(width: 82, height: 23)
                .padding(.top, 9)
                .allowsHitTesting(false)
        }
        .frame(width: 240, height: 510)
        .background(Color(hex: 0x0D0D0F))
        .clipShape(RoundedRectangle(cornerRadius: 46, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 46, style: .continuous)
            .strokeBorder(OnboardingTheme.warmBlack(0.05), lineWidth: 2))
        .shadow(color: OnboardingTheme.warmBlack(0.3), radius: 28, y: 26)
    }
}
