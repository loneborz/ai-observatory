import Foundation

enum MenuBarAppearance: Equatable {
    case percent(Int, nearExhaustion: Bool)
    case glyph
}

enum UsageDisplay {
    static let nearExhaustionPercent = 95

    static func remainingPercent(for usedPercent: Int?) -> Int? {
        guard let usedPercent else {
            return nil
        }
        let clampedUsedPercent = min(max(usedPercent, 0), 100)
        return 100 - clampedUsedPercent
    }

    static func constrainingWindow(in windows: [UsageWindow]) -> UsageWindow? {
        windows
            .filter { $0.usedPercent != nil }
            .max { lhs, rhs in
                let leftPercent = lhs.usedPercent ?? Int.min
                let rightPercent = rhs.usedPercent ?? Int.min
                if leftPercent != rightPercent {
                    return leftPercent < rightPercent
                }
                let leftDuration = lhs.windowDurationMins ?? Int.max
                let rightDuration = rhs.windowDurationMins ?? Int.max
                return leftDuration > rightDuration
            }
    }

    static func additionalWindows(in windows: [UsageWindow]) -> [UsageWindow] {
        guard let constraining = constrainingWindow(in: windows) else {
            return windows
        }
        return windows.filter { $0.id != constraining.id }
    }

    static func menuBarAppearance(for state: UsageViewState) -> MenuBarAppearance {
        guard case .available(let snapshot) = state,
              let percent = snapshot.constrainingRemainingPercent
        else {
            return .glyph
        }
        return .percent(percent, nearExhaustion: snapshot.emphasizesNearExhaustion)
    }

    static func showsCredits(hasCredits: Bool?, balance: String?) -> Bool {
        if hasCredits == true {
            return true
        }
        guard let balance else {
            return false
        }
        let trimmed = balance.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != "0"
    }

    static func showsLimitReached(_ reachedType: String?) -> Bool {
        guard let reachedType else {
            return false
        }
        return !reachedType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func planSubtitle(_ planType: String?) -> String? {
        guard let planType else {
            return nil
        }
        let trimmed = planType.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.localizedCapitalized
    }

    static func windowLabel(_ window: UsageWindow) -> String {
        if let minutes = window.windowDurationMins {
            return "\(formatDuration(minutes)) window"
        }
        return window.title
    }

    static func resetPhrase(_ date: Date?) -> String? {
        guard let date else {
            return nil
        }
        return "Resets \(resetFormatter.string(from: date))"
    }

    static func updatedPhrase(_ date: Date) -> String {
        "Updated \(updatedFormatter.string(from: date))"
    }

    static func creditsBalance(_ balance: String?) -> String? {
        guard let balance else {
            return nil
        }
        let trimmed = balance.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func logInvariantCheck() {
        let weekly = UsageWindow(id: "weekly", title: "codex", usedPercent: 72, windowDurationMins: 10_080, resetsAt: nil)
        let fiveHour = UsageWindow(id: "five", title: "codex", usedPercent: 40, windowDurationMins: 300, resetsAt: nil)
        let tiedFive = UsageWindow(id: "tied-five", title: "codex", usedPercent: 72, windowDurationMins: 300, resetsAt: nil)
        let unlabeled = UsageWindow(id: "none", title: "codex", usedPercent: nil, windowDurationMins: 60, resetsAt: nil)

        func check(_ name: String, _ passed: Bool) {
            fputs("usage-display-check: \(name)=\(passed ? "ok" : "FAIL")\n", stderr)
        }

        check("highest-percent", constrainingWindow(in: [fiveHour, weekly])?.id == "weekly")
        check("shorter-duration-on-tie", constrainingWindow(in: [weekly, tiedFive])?.id == "tied-five")
        check("ignore-missing-percent", constrainingWindow(in: [unlabeled, fiveHour])?.id == "five")
        check("no-invented-zero", constrainingWindow(in: [unlabeled]) == nil)
        check("remaining-conversion", remainingPercent(for: 72) == 28)
        check("remaining-clamps-low", remainingPercent(for: 105) == 0)
        check("remaining-clamps-high", remainingPercent(for: -5) == 100)
        check("remaining-preserves-missing", remainingPercent(for: nil) == nil)
        check(
            "healthy-below-95",
            menuBarAppearance(for: .available(snapshot(percent: 94, reached: nil))) == .percent(6, nearExhaustion: false)
        )
        check(
            "exhausted-at-95",
            menuBarAppearance(for: .available(snapshot(percent: 95, reached: nil))) == .percent(5, nearExhaustion: true)
        )
        check(
            "exhausted-reached-type",
            menuBarAppearance(for: .available(snapshot(percent: 10, reached: "primary"))) == .percent(90, nearExhaustion: true)
        )
        check(
            "constraining-window-uses-used-pressure",
            menuBarAppearance(for: .available(snapshot(windows: [weekly, fiveHour], reached: nil))) == .percent(28, nearExhaustion: false)
        )
        check("glyph-without-percent", menuBarAppearance(for: .available(snapshot(percent: nil, reached: nil))) == .glyph)
        check("glyph-on-error", menuBarAppearance(for: .error("Failed to read usage. Refresh later.")) == .glyph)
        check("hide-empty-credits", !showsCredits(hasCredits: false, balance: "0"))
    }

    private static func snapshot(percent: Int?, reached: String?) -> UsageSnapshot {
        snapshot(
            windows: [
                UsageWindow(id: "codex", title: "codex", usedPercent: percent, windowDurationMins: 10_080, resetsAt: nil)
            ],
            reached: reached
        )
    }

    private static func snapshot(windows: [UsageWindow], reached: String?) -> UsageSnapshot {
        UsageSnapshot(
            planType: "plus",
            windows: windows,
            hasCredits: false,
            creditBalance: "0",
            rateLimitReachedType: reached,
            earnedResetCount: 0,
            fetchedAt: Date()
        )
    }

    private static func formatDuration(_ minutes: Int) -> String {
        let day = 60 * 24
        if minutes >= day, minutes % day == 0 {
            let days = minutes / day
            return days == 1 ? "1-day" : "\(days)-day"
        }
        if minutes >= 60, minutes % 60 == 0 {
            let hours = minutes / 60
            return hours == 1 ? "1-hour" : "\(hours)-hour"
        }
        return "\(minutes) min"
    }

    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEEHm")
        return formatter
    }()

    private static let updatedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("Hm")
        return formatter
    }()
}

extension UsageSnapshot {
    var constrainingWindow: UsageWindow? {
        UsageDisplay.constrainingWindow(in: windows)
    }

    var constrainingUsedPercent: Int? {
        constrainingWindow?.usedPercent
    }

    var constrainingRemainingPercent: Int? {
        UsageDisplay.remainingPercent(for: constrainingUsedPercent)
    }

    var additionalWindows: [UsageWindow] {
        UsageDisplay.additionalWindows(in: windows)
    }

    var isNearExhaustion: Bool {
        if UsageDisplay.showsLimitReached(rateLimitReachedType) {
            return true
        }
        if let percent = constrainingUsedPercent, percent >= UsageDisplay.nearExhaustionPercent {
            return true
        }
        return false
    }

    /// Warning color is only for a real percent under quota stress, never for the empty glyph.
    var emphasizesNearExhaustion: Bool {
        constrainingUsedPercent != nil && isNearExhaustion
    }

    var showsCredits: Bool {
        UsageDisplay.showsCredits(hasCredits: hasCredits, balance: creditBalance)
    }

    var showsLimitReached: Bool {
        UsageDisplay.showsLimitReached(rateLimitReachedType)
    }
}
