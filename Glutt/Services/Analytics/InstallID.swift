import Foundation
import Security

/// A stable per-install identifier, durable across app deletes.
///
/// Two jobs:
///  - `ai_usage.install_id` on the proxy, so AI spend attributes to a device
///    before any account exists (and can be back-filled to a `user_id` at
///    sign-in).
///  - PostHog `distinct_id` before an account exists.
///
/// Keychain rather than `UserDefaults`, which is wiped when the app is deleted,
/// and rather than `identifierForVendor`, which resets once all our apps are
/// removed. Neither survives the reinstall this ID exists to see through.
///
/// Not personal data: a random UUID that identifies an installation, never a
/// person.
/// This type is compiled into BOTH the app and the GluttShare extension, which
/// have different bundle IDs and therefore separate Keychains by default. A
/// naive Keychain-only design would mint a *second* UUID inside the extension
/// and report one device as two. The shared app group — already configured on
/// both targets — is used as the cross-target channel: the Keychain provides
/// durability across reinstalls, the app group provides reach.
enum InstallID {
    private static let service = "com.malik.glutt.install"
    private static let account = "install-id"
    /// The pre-existing UserDefaults key, minted for Polly's abuse cap.
    private static let legacyDefaultsKey = "glutt.device.id"
    private static let sharedKey = "glutt.install.id"
    private static let appGroupID = "group.com.malik.glutt"

    private static var shared: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    /// Resolved once per launch — every proxy call reads this.
    private static let cached: String = resolve()

    static var current: String { cached }

    private static func resolve() -> String {
        // 1. Keychain: survives app deletion. Empty inside the extension.
        if let existing = readKeychain() {
            shared?.set(existing, forKey: sharedKey)
            return existing
        }

        // 2. App group: how the extension sees the app's ID, and how the app
        //    recovers if the Keychain read fails.
        if let sharedID = shared?.string(forKey: sharedKey), !sharedID.isEmpty {
            writeKeychain(sharedID)
            return sharedID
        }

        // 3. Migration, not a fresh mint. Devices already carry a UserDefaults
        //    ID from the Polly cap and `ai_usage` rows are already attributed
        //    to it. Minting a new UUID here would make every existing install
        //    look brand new and orphan its accumulated cost history.
        let id = UserDefaults.standard.string(forKey: legacyDefaultsKey) ?? UUID().uuidString

        // If the Keychain write fails we still return a usable ID for this
        // launch; the next launch retries. Attribution degrades, never breaks.
        writeKeychain(id)
        shared?.set(id, forKey: sharedKey)
        return id
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func readKeychain() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }
        return value
    }

    private static func writeKeychain(_ id: String) {
        var attributes = baseQuery()
        attributes[kSecValueData as String] = Data(id.utf8)
        // AfterFirstUnlock so a background import or notification can still
        // attribute; the default (WhenUnlocked) would fail with the phone locked.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        SecItemDelete(baseQuery() as CFDictionary)
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
