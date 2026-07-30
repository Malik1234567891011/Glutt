import Foundation
import Observation
import Supabase
import SuperwallKit

/// Who is signed in. The second axis of the launch state machine — the first is
/// `SubscriptionGate` (are they entitled), and the two are deliberately
/// independent: paying does not sign you in, and signing in does not unlock the
/// app.
///
/// Every row in `profiles` is therefore a paying customer, because the only
/// place that asks for a sign-in is *after* a purchase (see `RootView`).
@MainActor
@Observable
final class AccountSession {
    enum State: Equatable {
        /// Reading the stored session at launch. Brief; shows the same neutral
        /// splash as an unresolved entitlement.
        case resolving
        case signedOut
        case signedIn(userID: UUID, email: String?)
    }

    /// Thrown when "Log in" is used by someone who has never signed up.
    ///
    /// There is no sign-in-only mode for OIDC: exchanging an Apple or Google
    /// token *creates* the Supabase user when none exists. So the account is
    /// created, recognised as brand new, and deleted again before this is
    /// thrown — see `signIn(requireExisting:)`.
    enum AccountError: LocalizedError {
        case noAccountYet

        var errorDescription: String? {
            "You don't have an account yet. Go through setup to create one."
        }
    }

    private(set) var state: State = .resolving

    /// Set when someone dismisses the sign-in screen after it failed on them.
    /// Deliberately **not** persisted: a backend outage should cost one launch,
    /// never the account. Next cold start asks again.
    private(set) var deferredThisLaunch = false

    var userID: UUID? {
        if case let .signedIn(userID, _) = state { return userID }
        return nil
    }

    @ObservationIgnored private var watcher: Task<Void, Never>?

    /// Begins restoring and observing the session. Idempotent; call from the
    /// host view's `.task`.
    func start() {
        guard watcher == nil else { return }
        // `authStateChanges` always emits `.initialSession` first, so this both
        // restores the stored session and watches for later changes — no
        // separate restore path to keep in sync.
        watcher = Task { [weak self] in
            for await (event, session) in Backend.client.auth.authStateChanges {
                guard let self else { return }
                switch event {
                case .signedOut, .userDeleted:
                    self.apply(nil)
                default:
                    self.apply(session)
                }
            }
        }
    }

    /// Exchanges an Apple identity token for a Supabase session.
    ///
    /// `rawNonce` is the *unhashed* value; Apple was handed its SHA256. Supabase
    /// hashes this one itself and compares, which is what stops a stolen token
    /// from being replayed.
    ///
    /// `fullName` is only ever non-nil on a user's **first** authorization —
    /// Apple never returns it again — so it is written to the profile
    /// immediately.
    /// `requireExisting` is the "Already have an account? Log in" path: someone
    /// who has never signed up must be turned away rather than quietly enrolled.
    func signIn(
        idToken: String,
        rawNonce: String,
        fullName: String?,
        requireExisting: Bool = false
    ) async throws {
        let session = try await Backend.client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: rawNonce)
        )
        if requireExisting { try await rejectIfJustCreated(session.user) }
        apply(session)
        await linkProfile(userID: session.user.id, fullName: fullName)
    }

    /// Exchanges a Google identity token for a Supabase session.
    ///
    /// `rawNonce` is the same unhashed value handed to Google, which embeds it
    /// in the token verbatim. Google gives no display name separately, so
    /// whatever the token carries is what the signup trigger stores.
    func signInWithGoogle(
        idToken: String,
        accessToken: String,
        rawNonce: String,
        requireExisting: Bool = false
    ) async throws {
        let session = try await Backend.client.auth.signInWithIdToken(
            credentials: .init(
                provider: .google,
                idToken: idToken,
                accessToken: accessToken,
                // Raw, like Apple: GoTrue hashes this and compares it to the
                // token's claim, which is why Google was handed the hash.
                nonce: rawNonce
            )
        )
        if requireExisting { try await rejectIfJustCreated(session.user) }
        apply(session)
        await linkProfile(userID: session.user.id, fullName: nil)
    }

    /// Undoes an account that only exists because someone pressed "Log in".
    ///
    /// OIDC has no sign-in-only mode, so the only way to tell a returning user
    /// from a new one is to look at the row that just came back: a user created
    /// within seconds of this call had no account a moment ago.
    ///
    /// The window is deliberately generous. Being slightly too eager here costs
    /// a returning user one confusing message; being too strict enrolls a
    /// non-payer permanently and breaks the invariant that every row in
    /// `profiles` is a paying customer.
    ///
    /// Deleting needs the service-role key, so it goes through the same
    /// `delete-account` function as the Settings button, while the just-issued
    /// session is still valid. If that fails the account survives as an orphan,
    /// which is worth an alert — hence the event.
    private func rejectIfJustCreated(_ user: User) async throws {
        guard Date.now.timeIntervalSince(user.createdAt) < 30 else { return }

        do {
            try await Backend.client.functions.invoke("delete-account")
        } catch {
            Analytics.capture(.accountDeleteFailed, [
                "context": "login_without_account",
                "message": error.localizedDescription,
            ])
        }
        try? await Backend.client.auth.signOut()
        apply(nil)
        Analytics.capture(.loginWithoutAccount)
        throw AccountError.noAccountYet
    }

    /// Pushes the two onboarding answers that describe the *person* rather than
    /// a recipe: what they want from cooking, and what they will not eat.
    ///
    /// Two destinations because they answer two different questions.
    /// `profiles` gets them because otherwise a paying customer is a row
    /// holding an email and nothing else. PostHog gets them as person
    /// properties because "do people cooking for macros come back more" is a
    /// cohort question, and a PostHog cohort cannot join to Postgres.
    ///
    /// Best-effort, like `linkProfile` — this must never turn a good sign-in
    /// into a visible error.
    func syncTraits(goals: [String], dietaryRules: [String]) async {
        guard let userID else { return }
        Analytics.setPerson(["goals": goals, "dietary_rules": dietaryRules])
        do {
            try await Backend.client
                .from("profiles")
                .update(["goals": goals, "dietary_rules": dietaryRules])
                .eq("id", value: userID.uuidString)
                .execute()
        } catch {
            Analytics.capture(.profileLinkFailed, ["message": error.localizedDescription])
        }
    }

    /// Lets a signed-out user through after a failed attempt. See
    /// `deferredThisLaunch`.
    func deferSignIn() {
        deferredThisLaunch = true
    }

    func signOut() async {
        // Clear locally even if the network call fails — a user who taps sign
        // out must end up signed out.
        try? await Backend.client.auth.signOut()
        apply(nil)
    }

    /// Permanently deletes the account. Apple requires this path in-app once an
    /// app offers account creation (App Review 5.1.1(v)).
    ///
    /// The work happens in the `delete-account` Edge Function — removing an
    /// `auth.users` row needs the service-role key, which must never ship in
    /// the app. Throws so the caller can say it failed rather than silently
    /// leaving the account alive.
    func deleteAccount() async throws {
        try await Backend.client.functions.invoke("delete-account")
        // Stop filing this device's events under a person we just promised to
        // delete. Only here, never on sign out.
        Analytics.resetPerson()
        // The stored session now points at a user that no longer exists.
        try? await Backend.client.auth.signOut()
        apply(nil)
        // Do not immediately re-present the sign-in screen to someone who just
        // deleted their account. They are still entitled, so they keep the app;
        // the next cold launch asks again.
        deferredThisLaunch = true
    }

    // MARK: - Internals

    private func apply(_ session: Session?) {
        guard let session else {
            state = .signedOut
            return
        }

        let user = session.user
        state = .signedIn(userID: user.id, email: user.email)

        // Identify on every restore, not just at sign-in, so a returning user
        // is joined up from their first event of the launch. Both SDKs no-op
        // when the id is unchanged.
        //
        // The Supabase user id — NEVER the email. PostHog is a US installation
        // holding nothing but random UUIDs, and that is what keeps it a
        // non-issue; emails live in Supabase only.
        // The email is a person *property*, not the id — see `Analytics`. It is
        // what PostHog displays in place of the UUID, so the persons list reads
        // as customers rather than as hex.
        Analytics.identify(
            userID: user.id.uuidString,
            email: user.email,
            // Google puts a name in the token; Apple never does on a restore.
            name: user.userMetadata["full_name"]?.stringValue
        )
        // `-uiPreview` skips `Superwall.configure`, and touching `shared`
        // before that trips an assertionFailure in debug builds.
        if Superwall.isInitialized {
            Superwall.shared.identify(userId: user.id.uuidString)
        }
    }

    /// Writes what only the client knows: the Apple display name, and which
    /// install this person is signing in on.
    ///
    /// The install link is what turns device-level AI spend into a bill with a
    /// name on it, retroactively — `ai_spend_by_user` joins through it, so
    /// every call this device ever made attributes the moment the row lands.
    ///
    /// Best-effort — a failure here must not turn a successful sign-in into an
    /// error the user sees. Worst case the name is missing and their spend
    /// stays filed under the install.
    private func linkProfile(userID: UUID, fullName: String?) async {
        do {
            // Only send `display_name` when Apple actually gave one. Apple
            // returns it on the FIRST authorization and never again, so sending
            // nil later would null out an unrecoverable value.
            var profile = ["install_id": InstallID.current]
            if let fullName, !fullName.isEmpty { profile["display_name"] = fullName }

            try await Backend.client
                .from("profiles")
                .update(profile)
                .eq("id", value: userID.uuidString)
                .execute()

            // Idempotent: signing in again on the same phone is a no-op rather
            // than a duplicate-key error.
            try await Backend.client
                .from("profile_installs")
                .upsert(
                    ["user_id": userID.uuidString, "install_id": InstallID.current],
                    onConflict: "user_id,install_id",
                    ignoreDuplicates: true
                )
                .execute()
        } catch {
            Analytics.capture(.profileLinkFailed, ["message": error.localizedDescription])
        }
    }
}
