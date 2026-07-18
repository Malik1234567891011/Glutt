import SwiftUI

/// Screen 1 — H1 over a flex-fill rounded video frame (glutt-intro.mp4).
/// Content only; the coordinator owns the fixed "Continue" footer + chrome.
struct IntroVideoScreen: View {
    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeadline("Glutt is a whole new way to cook at home", size: 28, maxWidth: 310)
            videoFrame(resource: "glutt-intro", scale: 1.1, yOffset: -0.09, fadeHeight: 0.30)
                .padding(.vertical, 22)
        }
        .padding(.horizontal, 24)
        .padding(.top, 50)   // design 104 − 54
    }
}

/// Shared rounded-28 video frame with a top cream fade (screens 1 & 7).
func videoFrame(resource: String, scale: CGFloat, yOffset: CGFloat, fadeHeight: CGFloat) -> some View {
    ZStack(alignment: .top) {
        OnboardingTheme.videoFrame
        LoopingVideoView(resource: resource, scale: scale, yOffsetFraction: yOffset)
        GeometryReader { geo in
            LinearGradient(stops: [
                .init(color: OnboardingTheme.videoFrame, location: 0),
                .init(color: OnboardingTheme.videoFrame, location: 0.70),
                .init(color: OnboardingTheme.videoFrame.opacity(0), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .frame(height: geo.size.height * fadeHeight)
        }
        .allowsHitTesting(false)
    }
    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(OnboardingTheme.warmBlack(0.05), lineWidth: 1))
    .frame(maxHeight: .infinity)
}
