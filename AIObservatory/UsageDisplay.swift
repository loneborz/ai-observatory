import Foundation

struct MenuBarQuota: Equatable {
    let remainingPercent: Int
    let shortLabel: String
    let nearExhaustion: Bool
}

enum MenuBarAppearance: Equatable {
    case quotas([MenuBarQuota])
    case glyph
}

enum UsageDisplay {
    static let nearExhaustionPercent = 95
    static let fiveHourWindowDurationMins = 300
    static let sevenDayWindowDurationMins = 10_080

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

    static func primaryQuotaWindows(in windows: [UsageWindow]) -> [UsageWindow] {
        let available = windows.filter { $0.usedPercent != nil }
        let fiveHour = preferredWindow(withDuration: fiveHourWindowDurationMins, in: available)
        let sevenDay = preferredWindow(withDuration: sevenDayWindowDurationMins, in: available)
        let identified = [fiveHour, sevenDay].compactMap { $0 }

        if !identified.isEmpty {
            return identified
        }
        return constrainingWindow(in: available).map { [$0] } ?? []
    }

    static func additionalWindows(in windows: [UsageWindow], excluding displayedWindows: [UsageWindow]) -> [UsageWindow] {
        let displayedIDs = Set(displayedWindows.map(\.id))
        return windows.filter { !displayedIDs.contains($0.id) }
    }

    static func menuBarAppearance(for state: UsageViewState) -> MenuBarAppearance {
        guard case .available(let snapshot) = state else {
            return .glyph
        }

        let quotas = primaryQuotaWindows(in: snapshot.windows).compactMap { window -> MenuBarQuota? in
            guard let remainingPercent = remainingPercent(for: window.usedPercent) else {
                return nil
            }
            return MenuBarQuota(
                remainingPercent: remainingPercent,
                shortLabel: compactWindowLabel(window),
                nearExhaustion: snapshot.emphasizesNearExhaustion(for: window)
            )
        }

        guard !quotas.isEmpty else {
            return .glyph
        }
        return .quotas(quotas)
    }

    static func isNearExhaustion(
        for window: UsageWindow,
        constrainingWindow: UsageWindow?,
        reachedType: String?
    ) -> Bool {
        guard let usedPercent = window.usedPercent else {
            return false
        }
        if usedPercent >= nearExhaustionPercent {
            return true
        }
        return window.id == constrainingWindow?.id && showsLimitReached(reachedType)
    }

    static func compactWindowLabel(_ window: UsageWindow) -> String {
        if let minutes = window.windowDurationMins {
            if minutes == fiveHourWindowDurationMins {
                return "5H"
            }
            if minutes == sevenDayWindowDurationMins {
                return "7D"
            }
            let day = 60 * 24
            if minutes >= day, minutes % day == 0 {
                return "\(minutes / day)D"
            }
            if minutes >= 60, minutes % 60 == 0 {
                return "\(minutes / 60)H"
            }
            return "\(minutes)M"
        }

        let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Quota" : String(title.prefix(5)).uppercased()
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
        check("remaining-5h", remainingPercent(for: fiveHour.usedPercent) == 60)
        check("remaining-7d", remainingPercent(for: weekly.usedPercent) == 28)
        check("remaining-clamps-low", remainingPercent(for: 105) == 0)
        check("remaining-clamps-high", remainingPercent(for: -5) == 100)
        check("remaining-preserves-missing", remainingPercent(for: nil) == nil)
        check(
            "window-identification-ignores-payload-order",
            primaryQuotaWindows(in: [weekly, fiveHour]).map(\.id) == ["five", "weekly"]
        )
        check(
            "both-window-rendering-state",
            menuBarAppearance(for: .available(snapshot(windows: [weekly, fiveHour], reached: nil))) == .quotas([
                MenuBarQuota(remainingPercent: 60, shortLabel: "5H", nearExhaustion: false),
                MenuBarQuota(remainingPercent: 28, shortLabel: "7D", nearExhaustion: false),
            ])
        )
        check(
            "5h-only-rendering-state",
            menuBarAppearance(for: .available(snapshot(windows: [fiveHour], reached: nil))) == .quotas([
                MenuBarQuota(remainingPercent: 60, shortLabel: "5H", nearExhaustion: false),
            ])
        )
        check(
            "7d-only-rendering-state",
            menuBarAppearance(for: .available(snapshot(windows: [weekly], reached: nil))) == .quotas([
                MenuBarQuota(remainingPercent: 28, shortLabel: "7D", nearExhaustion: false),
            ])
        )
        let warningFiveHour = UsageWindow(id: "warning-five", title: "codex", usedPercent: 95, windowDurationMins: 300, resetsAt: nil)
        let healthyWeekly = UsageWindow(id: "healthy-weekly", title: "codex", usedPercent: 50, windowDurationMins: 10_080, resetsAt: nil)
        check(
            "independent-warning-boundaries",
            menuBarAppearance(for: .available(snapshot(windows: [healthyWeekly, warningFiveHour], reached: nil))) == .quotas([
                MenuBarQuota(remainingPercent: 5, shortLabel: "5H", nearExhaustion: true),
                MenuBarQuota(remainingPercent: 50, shortLabel: "7D", nearExhaustion: false),
            ])
        )
        let healthyFiveHour = UsageWindow(id: "healthy-five", title: "codex", usedPercent: 50, windowDurationMins: 300, resetsAt: nil)
        let warningWeekly = UsageWindow(id: "warning-weekly", title: "codex", usedPercent: 95, windowDurationMins: 10_080, resetsAt: nil)
        check(
            "independent-warning-boundaries-reversed",
            menuBarAppearance(for: .available(snapshot(windows: [warningWeekly, healthyFiveHour], reached: nil))) == .quotas([
                MenuBarQuota(remainingPercent: 50, shortLabel: "5H", nearExhaustion: false),
                MenuBarQuota(remainingPercent: 5, shortLabel: "7D", nearExhaustion: true),
            ])
        )
        check(
            "reached-type-still-warns-constraining-window",
            menuBarAppearance(for: .available(snapshot(percent: 10, reached: "primary"))) == .quotas([
                MenuBarQuota(remainingPercent: 90, shortLabel: "7D", nearExhaustion: true),
            ])
        )
        check("missing-percentage-state", menuBarAppearance(for: .available(snapshot(percent: nil, reached: nil))) == .glyph)
        check("glyph-on-error", menuBarAppearance(for: .error("Failed to read usage. Refresh later.")) == .glyph)
        check("hide-empty-credits", !showsCredits(hasCredits: false, balance: "0"))
    }

    private static func preferredWindow(withDuration duration: Int, in windows: [UsageWindow]) -> UsageWindow? {
        windows
            .filter { $0.windowDurationMins == duration }
            .max { lhs, rhs in
                let leftPercent = lhs.usedPercent ?? Int.min
                let rightPercent = rhs.usedPercent ?? Int.min
                if leftPercent != rightPercent {
                    return leftPercent < rightPercent
                }
                return lhs.id > rhs.id
            }
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

    var primaryQuotaWindows: [UsageWindow] {
        UsageDisplay.primaryQuotaWindows(in: windows)
    }

    var additionalWindows: [UsageWindow] {
        UsageDisplay.additionalWindows(in: windows, excluding: primaryQuotaWindows)
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
        guard let constrainingWindow else {
            return false
        }
        return emphasizesNearExhaustion(for: constrainingWindow)
    }

    func emphasizesNearExhaustion(for window: UsageWindow) -> Bool {
        UsageDisplay.isNearExhaustion(
            for: window,
            constrainingWindow: constrainingWindow,
            reachedType: rateLimitReachedType
        )
    }

    var showsCredits: Bool {
        UsageDisplay.showsCredits(hasCredits: hasCredits, balance: creditBalance)
    }

    var showsLimitReached: Bool {
        UsageDisplay.showsLimitReached(rateLimitReachedType)
    }
}
