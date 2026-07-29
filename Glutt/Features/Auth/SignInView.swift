import AuthenticationServices
import SwiftUI

/// Sign in with Apple. Appears in exactly two places:
///
///  - **After a purchase** (`RootView`), where it is not dismissible — the
///    person just paid and we want a durable record of who they are.
///  - **From `WelcomeScreen`** ("Already have an account? Log in"), as a sheet,
///    for someone reinstalling or on a new phone.
///
/// Signing in does not unlock anything: the subscription is restored from the
/// Apple ID by StoreKit regardless. This is identity only.
struct SignInView: View {
    let session: AccountSession
    /// True for the Welcome sheet, false for the post-purchase presentation.
    var canDismiss = false
    var onDismiss: (() -> Void)?

    @State private var rawNonce = AppleSignIn.makeNonce()
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            OnboardingTheme.cream.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                MS.skilletFill.sized(46).foregroundStyle(OnboardingTheme.greenDeep)
                    .padding(.bottom, 26)

                OnboardingHeadline("Save your place", size: 27, maxWidth: 300)
                OnboardingSubhead("Sign in so your subscription follows you to a new phone.")
                    .padding(.top, 8)

                Spacer(minLength: 0)

                if let errorMessage {
                    Text(errorMessage)
                        .font(OnboardingFonts.nunito(13.5, 600))
                        .foregroundStyle(OnboardingTheme.mutedWarm)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 14)
                        .transition(.opacity)
                }

                // Both providers share one button so they read as siblings:
                // same height, same corner, same typeface. Apple's own
                // `SignInWithAppleButton` renders in the system font and cannot
                // be restyled, which made the pair look like two different apps.
                ProviderButton(
                    label: "Sign in with Apple",
                    background: .black,
                    foreground: .white,
                    bordered: false,
                    isWorking: isWorking,
                    action: appleTapped
                ) {
                    Image(systemName: "applelogo")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                        // Apple's mark sits slightly high at its own baseline.
                        .offset(y: -1)
                }

                if GoogleAuth.isConfigured {
                    ProviderButton(
                        label: "Continue with Google",
                        background: .white,
                        foreground: OnboardingTheme.textHeading,
                        bordered: true,
                        isWorking: isWorking,
                        action: googleTapped
                    ) {
                        // Google's own four-colour mark, vendored from their
                        // branding guidelines. Deliberately NOT a template
                        // asset: tinting it would break the trademark.
                        Image("googleG")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 19, height: 19)
                    }
                    .padding(.top, 12)
                }

                // Only offered once something has actually gone wrong. A paying
                // customer must never be trapped behind our backend being down —
                // they keep the app, and the next cold launch asks again.
                if errorMessage != nil, !canDismiss {
                    OnboardingTextLink(title: "Continue without an account") {
                        Analytics.capture(.signInDeferred)
                        session.deferSignIn()
                    }
                    .padding(.top, 18)
                }

                // Provider-neutral now that Google is an option too.
                Text("Glutt only ever sees your name and email. Never your password.")
                    .font(OnboardingFonts.nunito(11.5, 600))
                    .foregroundStyle(OnboardingTheme.timestamp)
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 22)
            .animation(.easeInOut(duration: 0.2), value: errorMessage)
        }
        .overlay(alignment: .topTrailing) {
            if canDismiss {
                Button { onDismiss?() } label: {
                    MS.closeIcon.sized(20).foregroundStyle(OnboardingTheme.mutedDeep)
                        .padding(12)
                }
                .padding(.top, 8).padding(.trailing, 8)
                .accessibilityLabel("Close")
            }
        }
    }

    private func appleTapped() {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                let credential = try await AppleSignIn.credential(rawNonce: rawNonce)
                try await session.signIn(
                    idToken: credential.idToken,
                    rawNonce: rawNonce,
                    fullName: credential.fullName
                )
                Analytics.capture(.signInSucceeded, ["provider": "apple"])
                if canDismiss { onDismiss?() }
            } catch {
                // Tapping Cancel is a choice, not an error. Say nothing and let
                // them press the button again.
                if AppleSignIn.isCancellation(error) {
                    isWorking = false
                    return
                }
                fail(Self.message(for: error), detail: error.localizedDescription)
            }
            isWorking = false
        }
    }

    /// `localizedDescription` on these errors is developer text — the raw
    /// `AuthorizationError error 1000.` string is not something to show someone
    /// who just paid. The real text still rides along on the analytics event,
    /// where it is useful.
    private static func message(for error: Error) -> String {
        guard let authError = error as? ASAuthorizationError else {
            return "Couldn't finish signing in. Please try again in a moment."
        }
        switch authError.code {
        case .unknown:
            // Overwhelmingly this is "no Apple Account on this device" — iOS
            // shows its own alert first and then hands us a bare 1000.
            return "You need to be signed in to an Apple Account on this iPhone. Open Settings, sign in, then try again."
        default:
            return "Apple couldn't complete the sign-in. Please try again."
        }
    }

    private func googleTapped() {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                let tokens = try await GoogleAuth.tokens(rawNonce: rawNonce)
                try await session.signInWithGoogle(
                    idToken: tokens.idToken,
                    accessToken: tokens.accessToken,
                    rawNonce: rawNonce
                )
                Analytics.capture(.signInSucceeded, ["provider": "google"])
                if canDismiss { onDismiss?() }
            } catch {
                // Backing out of Google's sheet says nothing; let them press
                // the button again.
                if GoogleAuth.isCancellation(error) {
                    isWorking = false
                    return
                }
                fail(
                    "Couldn't finish signing in with Google. Please try again.",
                    detail: error.localizedDescription
                )
            }
            isWorking = false
        }
    }

    private func fail(_ message: String, detail: String) {
        errorMessage = message
        isWorking = false
        // A nonce is single-use: a retry with the spent one is rejected.
        rawNonce = AppleSignIn.makeNonce()
        Analytics.capture(.signInFailed, ["detail": detail])
    }
}

/// One button shape for every provider, so the stack reads as a set rather than
/// as whatever each SDK happened to ship.
private struct ProviderButton<Icon: View>: View {
    let label: String
    let background: Color
    let foreground: Color
    let bordered: Bool
    let isWorking: Bool
    let action: () -> Void
    @ViewBuilder let icon: Icon

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon
                Text(label)
                    .font(OnboardingFonts.nunito(17, 800))
                    .foregroundStyle(foreground)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(background, in: Capsule())
            .overlay {
                if bordered {
                    Capsule().strokeBorder(OnboardingTheme.warmBlack(0.12), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .opacity(isWorking ? 0.5 : 1)
    }
}

#Preview {
    SignInView(session: AccountSession())
}
