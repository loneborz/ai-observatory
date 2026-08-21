import Foundation

struct UsageResetBoundary: Equatable, Sendable {
    let windowID: String
    let date: Date
}

struct UsageRefreshSchedule: Sendable {
    static let interval: TimeInterval = 15 * 60

    private(set) var nextAutomaticRefreshAt: Date?
    private(set) var handledResetBoundary: UsageResetBoundary?

    func overdueResetBoundary(in snapshot: UsageSnapshot?, at now: Date) -> UsageResetBoundary? {
        guard let window = snapshot?.constrainingWindow,
              let resetsAt = window.resetsAt,
              resetsAt <= now
        else {
            return nil
        }
        let boundary = UsageResetBoundary(windowID: window.id, date: resetsAt)
        return boundary == handledResetBoundary ? nil : boundary
    }

    func shouldRefresh(snapshot: UsageSnapshot?, at now: Date) -> Bool {
        guard let snapshot else {
            return nextAutomaticRefreshAt.map { now >= $0 } ?? true
        }
        if now.timeIntervalSince(snapshot.fetchedAt) >= Self.interval {
            return true
        }
        return (nextAutomaticRefreshAt.map { now >= $0 } ?? false)
            || overdueResetBoundary(in: snapshot, at: now) != nil
    }

    mutating func beginAttempt(at now: Date, handling resetBoundary: UsageResetBoundary? = nil) {
        nextAutomaticRefreshAt = now.addingTimeInterval(Self.interval)
        if let resetBoundary {
            handledResetBoundary = resetBoundary
        }
    }

    mutating func recordSuccess(_ snapshot: UsageSnapshot) {
        nextAutomaticRefreshAt = snapshot.fetchedAt.addingTimeInterval(Self.interval)
    }

    func nextDate(snapshot: UsageSnapshot?, at now: Date) -> Date {
        let cadence = nextAutomaticRefreshAt ?? now.addingTimeInterval(Self.interval)
        guard let window = snapshot?.constrainingWindow,
              let resetsAt = window.resetsAt,
              resetsAt > now
        else {
            return cadence
        }
        let boundary = UsageResetBoundary(windowID: window.id, date: resetsAt)
        return boundary == handledResetBoundary ? cadence : min(cadence, resetsAt)
    }
}

#if DEBUG
extension UsageRefreshSchedule {
    static func logInvariantCheck() {
        let start = Date(timeIntervalSince1970: 1_767_000_000)
        let reset = start.addingTimeInterval(5 * 60)
        let snapshot = UsageSnapshot(
            planType: "plus",
            windows: [
                UsageWindow(
                    id: "weekly",
                    title: "codex",
                    usedPercent: 72,
                    windowDurationMins: 10_080,
                    resetsAt: reset
                ),
            ],
            hasCredits: false,
            creditBalance: "0",
            rateLimitReachedType: nil,
            earnedResetCount: 0,
            fetchedAt: start
        )

        var schedule = UsageRefreshSchedule()
        schedule.beginAttempt(at: start)
        schedule.recordSuccess(snapshot)

        func check(_ name: String, _ passed: Bool) {
            fputs("usage-refresh-check: \(name)=\(passed ? "ok" : "FAIL")\n", stderr)
        }

        check("cadence-not-early", !schedule.shouldRefresh(snapshot: snapshot, at: start.addingTimeInterval(60)))
        check("reset-schedules-early", schedule.nextDate(snapshot: snapshot, at: start) == reset)
        check("reset-boundary-due", schedule.shouldRefresh(snapshot: snapshot, at: reset))
        let boundary = schedule.overdueResetBoundary(in: snapshot, at: reset)
        schedule.beginAttempt(at: reset, handling: boundary)
        check("reset-boundary-once", !schedule.shouldRefresh(snapshot: snapshot, at: reset.addingTimeInterval(1)))
        check("cadence-due", schedule.shouldRefresh(snapshot: snapshot, at: start.addingTimeInterval(Self.interval)))
    }
}
#endif
