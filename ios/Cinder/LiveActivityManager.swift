import ActivityKit
import Foundation

/// Starts, updates and ends the lock-screen countdown.
/// Without a paid developer account there are no server pushes, so the
/// activity can only be started or refreshed while the app is open.
enum LiveActivityManager {
    static var isRunning: Bool { !Activity<CinderAttributes>.activities.isEmpty }
    static var isAllowed: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    static func sync(with stats: Stats, autoStart: Bool) async {
        let mood = CinderLogic.mood(stats)
        let state = CinderAttributes.ContentState(
            streak: stats.streak.current,
            done: stats.isFromToday() ? stats.goalDone : 0,
            target: stats.goalTarget,
            mood: mood,
            stage: CinderLogic.displayedStage(stats, mood: mood)
        )
        let dayEnd = CinderLogic.dayEnd(dayStartHour: stats.dayStartHour)

        if mood == .lit {
            await endAll(final: state)
            return
        }
        if let current = Activity<CinderAttributes>.activities.first {
            if current.attributes.dayEnd != dayEnd {
                await endAll(final: state)
            } else {
                await current.update(ActivityContent(state: state, staleDate: dayEnd))
                return
            }
        }
        guard autoStart, isAllowed else { return }
        _ = try? Activity.request(
            attributes: CinderAttributes(dayEnd: dayEnd),
            content: ActivityContent(state: state, staleDate: dayEnd),
            pushType: nil
        )
    }

    static func endAll(final state: CinderAttributes.ContentState? = nil) async {
        for activity in Activity<CinderAttributes>.activities {
            let content = state.map { ActivityContent(state: $0, staleDate: nil) }
            await activity.end(content, dismissalPolicy: .immediate)
        }
    }
}
