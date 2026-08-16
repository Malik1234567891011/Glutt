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
        // `.freeTrialStart` rather than `.transactionComplete`: that one also
        // fires for a straight subscription purchase, and Events Manager is
        // configured for the trial alone. Superwall raises this one only when
        // the purchased product carried an introductory offer, which is what
        // Meta means by a trial.
        guard case let .freeTrialStart(product, _) = eventInfo.event else { return }

        MetaAds.logTrialStarted(
            productID: product.productIdentifier,
            price: product.price,
            currencyCode: product.currencyCode
        )
    }
}
