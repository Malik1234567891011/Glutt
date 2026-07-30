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

    /// Local/dev media playback base (media-worker `serve-local`). Optional.
    static let mediaPlaybackBaseURL: String? = {
        let v = local["mediaPlaybackBaseURL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (v?.isEmpty == false) ? v : nil
    }()

    /// Supabase project (accounts). Committed defaults, not secrets: the URL is
    /// public and the publishable key is designed to ship in clients — every
    /// table it can reach is guarded by RLS. The service-role key, which
    /// bypasses RLS, lives only in the proxy's Vercel env and must never appear
    /// in this file or the app bundle.
    private static let defaultSupabaseURL = "https://mlgdtksukpifkmhqulnc.supabase.co"

    static var supabaseURL: URL {
        // Falls back rather than crashing: a malformed override in the plist
        // should cost you accounts, not the whole app on launch.
        if let override = local["supabaseURL"], let url = URL(string: override) { return url }
        return URL(string: defaultSupabaseURL)!
    }

    static let supabaseKey = local["supabaseKey"] ?? "sb_publishable_mCsKYQt-qRWbvyIljJIOSw_Rn2cJwPS"

    /// Google **iOS** OAuth client id, for native Google sign-in. Public by
    /// design (it identifies the app, it does not authorize anything on its
    /// own), which is why it also appears reversed as a URL scheme in
    /// `project.yml`. Those two must always match.
    ///
    /// Empty hides the Google button rather than shipping one that cannot work.
    static let googleClientID = local["googleClientID"]
        ?? "326973383718-tmur4tp76aicsnvih43tkn36u7aj44tk.apps.googleusercontent.com"
}
