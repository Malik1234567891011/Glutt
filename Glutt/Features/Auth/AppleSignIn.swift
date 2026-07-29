import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// The nonce dance behind Sign in with Apple.
///
/// Apple is handed the **SHA256** of a random string and embeds it in the
/// identity token; Supabase is handed the **raw** string and hashes it itself
/// to compare. A token lifted off the wire is therefore useless without the
/// raw value, which never leaves the device until the exchange.
///
/// The flow is driven directly rather than through SwiftUI's
/// `SignInWithAppleButton`, because that button renders in the system font and
/// cannot be restyled. Next to a Google button in Glutt's own typeface it read
/// as two buttons from two different apps. Apple's guidelines allow a custom
/// button provided it keeps the mark, the approved wording, and enough contrast,
/// which the pair in `SignInView` does.
enum AppleSignIn {
    enum Failure: LocalizedError {
        case noIdentityToken

        var errorDescription: String? {
            switch self {
            case .noIdentityToken: "Apple didn't return a usable sign-in."
            }
        }
    }

    /// Presents Apple's sheet and returns the identity token to exchange, plus
    /// the display name if this is the user's first authorization.
    @MainActor
    static func credential(rawNonce: String) async throws -> (idToken: String, fullName: String?) {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(rawNonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        return try await Coordinator().perform(controller)
    }

    /// Backing out is a choice, not a failure.
    static func isCancellation(_ error: Error) -> Bool {
        (error as? ASAuthorizationError)?.code == .canceled
    }

    /// Bridges `ASAuthorizationController`'s delegate callbacks to async/await.
    /// It retains itself for the duration, because the controller holds its
    /// delegate weakly and nothing else keeps this alive across the await.
    private final class Coordinator: NSObject,
        ASAuthorizationControllerDelegate,
        ASAuthorizationControllerPresentationContextProviding
    {
        private var continuation: CheckedContinuation<(idToken: String, fullName: String?), Error>?
        private var selfReference: Coordinator?

        @MainActor
        func perform(
            _ controller: ASAuthorizationController
        ) async throws -> (idToken: String, fullName: String?) {
            controller.delegate = self
            controller.presentationContextProvider = self
            selfReference = self
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                controller.performRequests()
            }
        }

        private func finish(_ result: Result<(idToken: String, fullName: String?), Error>) {
            continuation?.resume(with: result)
            continuation = nil
            selfReference = nil
        }

        func authorizationController(
            controller: ASAuthorizationController,
            didCompleteWithAuthorization authorization: ASAuthorization
        ) {
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let unpacked = AppleSignIn.unpack(credential)
            else {
                finish(.failure(Failure.noIdentityToken))
                return
            }
            finish(.success(unpacked))
        }

        func authorizationController(
            controller: ASAuthorizationController,
            didCompleteWithError error: Error
        ) {
            finish(.failure(error))
        }

        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow }
                ?? UIWindow()
        }
    }
    /// One per authorization attempt. Regenerate for every button press —
    /// reusing a nonce defeats the point of having one.
    static func makeNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        // Falls back to UUIDs only if the system RNG refuses, which in practice
        // does not happen; better than trapping mid-sign-in.
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return UUID().uuidString + UUID().uuidString
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// What Apple receives — the hash, never the raw nonce.
    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The two things a credential is worth: the identity token to exchange,
    /// and the display name — which Apple returns **only on the very first
    /// authorization**, never again.
    static func unpack(
        _ credential: ASAuthorizationAppleIDCredential
    ) -> (idToken: String, fullName: String?)? {
        guard let data = credential.identityToken,
              let token = String(data: data, encoding: .utf8)
        else { return nil }

        let name = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)

        return (token, name.isEmpty ? nil : name)
    }
}
