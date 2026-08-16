import Foundation
import SuperwallKit

/// Relays Superwall's checkout outcomes to `MetaAds`.
///
/// Superwall owns the purchase, so it is the only thing that knows a trial
/// actually *started*. `SubscriptionGate` only sees the result — entitlement
/// flipping to active — and cannot tell a fresh trial from a restore on a new
/// phone or a renewal, which is precisely the distinction Meta's `StartTrial`
/// conversion is.
///
/// `Superwall.shared.delegate` is weak, so `GluttApp` holds this. A bridge that
/// deallocates is a campaign with no conversions and nothing in any log to say
/// why.
@MainActor
final class PaywallEventBridge: SuperwallDelegate {
    func handleSuperwallEvent(withInfo eventInfo: SuperwallEventInfo) {
        // These two rather than `.transactionComplete`, which fires alongside
        // both and would double every conversion.
        //
        // Which one Superwall raises is decided by StoreKit, not by the paywall:
        // `.freeTrialStart` only when the purchased product still carried an
        // introductory offer for that Apple ID. Someone who used their trial on
        // a previous install buys straight through and lands in the second case.
        switch eventInfo.event {
        case let .freeTrialStart(product, _):
            MetaAds.logTrialStarted(
                productID: product.productIdentifier,
                price: product.price,
                currencyCode: product.currencyCode
            )
        case let .subscriptionStart(product, _):
            MetaAds.logSubscribed(
                productID: product.productIdentifier,
                price: product.price,
                currencyCode: product.currencyCode
            )
        default:
            break
        }
    }
}
