import GoogleSignIn
import UIKit

/// Native Google sign-in, reduced to the two tokens Supabase needs.
///
/// Named `GoogleAuth` rather than `GoogleSignIn` so the type does not collide
/// with the module it imports.
///
/// **No nonce, on either side.** This flow shipped passing the same raw nonce
/// to Google and to Supabase, on the reasoning that Google embeds it verbatim.
/// It cannot work: GoogleSignIn does forward the nonce unchanged into the
/// token's `nonce` claim, but GoTrue compares that claim against the *SHA256*
/// of the nonce it was given, which is Apple's convention. Raw on one side,
/// hashed on the other, so every attempt returned `Nonces mismatch`.
///
/// Supabase's own native-Google example passes no nonce at all, and their iOS
/// guide says to enable "Skip nonce check" on the provider. Sending nothing
/// matches both and needs no dashboard switch. Apple keeps its nonce dance,
/// where hashing is exactly what is required.
enum GoogleAuth {
    /// False when no client id is configured, which is the signal to hide the
    /// button instead of offering a flow that cannot complete.
    static var isConfigured: Bool { !Secrets.googleClientID.isEmpty }

    enum Failure: LocalizedError {
        case notConfigured
        case noPresenter
        case noIdentityToken

        var errorDescription: String? {
            switch self {
            case .notConfigured: "Google sign-in isn't available in this build."
            case .noPresenter: "Couldn't open Google sign-in. Please try again."
            case .noIdentityToken: "Google didn't return a usable sign-in."
            }
        }
    }

    /// Presents Google's sheet and returns the tokens for the Supabase exchange.
    /// Throws `GIDSignInError.canceled` when the user backs out, which callers
    /// should treat as a choice rather than an error.
    @MainActor
    static func tokens() async throws -> (idToken: String, accessToken: String) {
        guard isConfigured else { throw Failure.notConfigured }
        guard let presenter else { throw Failure.noPresenter }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: Secrets.googleClientID)

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)

        guard let idToken = result.user.idToken?.tokenString else {
            throw Failure.noIdentityToken
        }
        return (idToken, result.user.accessToken.tokenString)
    }

    /// Backing out of Google's sheet is a choice, not a failure. Kept here so
    /// the view layer never has to import the SDK to tell the difference.
    static func isCancellation(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == kGIDSignInErrorDomain
            && error.code == GIDSignInError.canceled.rawValue
    }

    /// The topmost view controller. Walks past anything already presented,
    /// because the sign-in screen is itself a sheet in the returning-user flow
    /// and presenting onto a controller that is already presenting fails.
    @MainActor
    private static var presenter: UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }

        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
