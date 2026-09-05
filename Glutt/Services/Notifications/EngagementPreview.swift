#if DEBUG
import Foundation
import UserNotifications

/// Fires one engagement notification a few seconds from now, so the real thing
/// can be looked at on a device instead of imagined from a string literal.
///
/// **Debug only, and reachable only from a launch argument.** There is no menu,
/// no button and no setting: a build a cook installs cannot get here at all.
/// It goes through `EngagementScheduler.request(for:in:)`, so what appears on
/// the lock screen is the production content, not a copy of it.
///
///     xcrun simctl launch <sim> com.omarlahmimi.glutt -notifyPreview useSoon
///
@MainActor
enum EngagementPreview {

    static let argument = "-notifyPreview"

    /// Its own identifier, deliberately.
    ///
    /// Sharing the production id looked right and was not: the scene becoming
    /// active calls `EngagementScheduler.refresh`, which clears whatever is
    /// pending under that id before re-planning, so the preview was scheduled
    /// and then immediately deleted by the app's own housekeeping. It took a
    /// log of `getPendingNotificationRequests` to see, because `add` reported
    /// no error at all.
    static let identifier = "glutt.engagement.preview"

    /// Reads the launch arguments and schedules a preview if one was asked for.
    static func scheduleIfRequested(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        center: UNUserNotificationCenter = .current()
    ) {
        guard let index = arguments.firstIndex(of: argument),
              arguments.index(after: index) < arguments.endIndex,
              let kind = EngagementPlanner.Kind(rawValue: arguments[arguments.index(after: index)])
        else { return }

        guard let plan = sample(kind) else { return }
        center.add(EngagementScheduler.request(for: plan, in: 10, identifier: identifier))
    }

    /// A representative plan per tier, built by the planner itself so the copy
    /// under inspection is the copy that ships.
    static func sample(_ kind: EngagementPlanner.Kind) -> EngagementPlanner.Plan? {
        // Morning, so every tier can build. `streakAtRisk` only plans when its
        // 19:00 slot is still ahead today, which is correct in production and
        // would silently return nil for a preview run after dinner.
        let calendar = Calendar.current
        let now = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
        var state = EngagementPlanner.State()
        let recipe = EngagementPlanner.SavedRecipe(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            title: "Creamy Lemon Chicken Rice Bowl",
            savedAt: now.addingTimeInterval(-5 * 86_400),
            totalMinutes: 45,
            ingredientCount: 8)

        switch kind {
        case .useSoon: state.useSoonItems = ["Spinach"]
        case .savedRecipe:
            state.savedNotCooked = [recipe]; state.savedRecipeCount = 9
        case .cookableNow:
            state.cookableNow = [recipe]; state.savedRecipeCount = 9
        case .streakAtRisk:
            state.savedRecipeCount = 9; state.skillStreak = 6
            state.streakNeedsToday = true
            state.nextSkill = .init(id: "knife.claw", title: "Claw Grip")
        case .skillInactive:
            state.savedRecipeCount = 9; state.hasStartedSkills = true
            state.lastSkillLearnedAt = now.addingTimeInterval(-7 * 86_400)
            state.nextSkill = .init(id: "knife.claw", title: "Claw Grip")
        case .emptyLibrary:
            state.savedRecipeCount = 0
        }
        return EngagementPlanner.plan(for: state, now: now)
    }
}
#endif
