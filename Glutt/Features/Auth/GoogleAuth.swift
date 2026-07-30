import GoogleSignIn
import UIKit

/// Native Google sign-in, reduced to the two tokens Supabase needs.
///
/// Named `GoogleAuth` rather than `GoogleSignIn` so the type does not collide
/// with the module it imports.
///
/// **Google takes the hashed nonce, Supabase takes the raw one** — the same
/// dance as Apple, and for the same reason.
///
/// This shipped sending the *raw* nonce to both, on the reasoning that Google
/// embeds it verbatim. Google does embed it verbatim; that is precisely the
/// problem. GoTrue hashes whatever nonce it is given and compares that against
/// the token's claim, for every provider — "If the ID token contains a nonce
/// claim, then the hash of this value is compared to the value in the ID
/// token." Raw in the token, hashed at the comparison, so every attempt came
/// back `Nonces mismatch`.
///
/// Dropping the nonce entirely was tried and is worse: Google hands back a
/// *cached* token from a previous sign-in, which still carries the old nonce
/// claim, and GoTrue then rejects the mismatched pair with "Passed nonce and
/// nonce in id_token should either both exist or not". Hence the `signOut()`
/// below — every attempt must mint a fresh token, or a stale one from an
/// earlier failed attempt poisons the next.
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
    static func tokens(rawNonce: String) async throws -> (idToken: String, accessToken: String) {
        guard isConfigured else { throw Failure.notConfigured }
        guard let presenter else { throw Failure.noPresenter }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: Secrets.googleClientID)

        // Discard any cached authorization first. Without this the SDK can
        // return the token it already holds, whose nonce claim belongs to an
        // earlier attempt and will never match the one we are about to send.
        GIDSignIn.sharedInstance.signOut()

        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: presenter,
            hint: nil,
            additionalScopes: nil,
            // The hash, exactly as Apple gets it. Supabase is handed the raw
            // value and hashes it to compare.
            nonce: AppleSignIn.sha256(rawNonce)
        )

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
