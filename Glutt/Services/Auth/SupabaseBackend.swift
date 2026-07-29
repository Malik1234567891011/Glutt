import Foundation
import Supabase

/// The one configured Supabase client.
///
/// Accounts are **identity only** — they do not unlock the app (the
/// subscription lives on the Apple ID and `SubscriptionGate` owns that
/// decision), and no recipe, Kitchen or cook data syncs here. What Supabase
/// holds is: who a paying customer is (`profiles`) and what their AI calls cost
/// (`ai_usage`, written server-side by the proxy).
///
/// Every table this client can reach is RLS-guarded, which is what makes the
/// publishable key safe to ship. See docs/plan-accounts-and-ai-usage.md.
enum Backend {
    static let client = SupabaseClient(
        supabaseURL: Secrets.supabaseURL,
        supabaseKey: Secrets.supabaseKey
    )
}
