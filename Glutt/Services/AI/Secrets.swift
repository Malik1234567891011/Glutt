import Foundation

/// App-level AI configuration.
///
/// The proxy client key lives in the gitignored `Secrets.local.plist`
/// (bundled into the app + share extension at build time) — never in git.
/// Copy `Secrets.local.example.plist` next to it, fill in the real key, and
/// run `xcodegen generate`. Without the plist the app still builds and runs;
/// cloud AI features are simply disabled (empty key → proxy rejects).
///
/// The client key is spam protection for the proxy, not a real secret — the
/// OPENAI_API_KEY never leaves the server. Rotation: the proxy accepts
/// GLUTT_PROXY_CLIENT_KEY and GLUTT_PROXY_CLIENT_KEY_NEXT simultaneously, so
/// shipped builds keep working while new builds carry the next key.
enum Secrets {
    private static let local: [String: String] = {
        guard let url = Bundle.main.url(forResource: "Secrets.local", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: String] else { return [:] }
        return dict
    }()

    /// Backend proxy base URL (not secret; committed default).
    static let aiProxyBaseURL = local["aiProxyBaseURL"] ?? "https://glutt-sable.vercel.app/api"

    /// Proxy client key; empty (AI features disabled) when the plist is absent.
    static let aiProxyClientKey = local["aiProxyClientKey"] ?? ""
}
