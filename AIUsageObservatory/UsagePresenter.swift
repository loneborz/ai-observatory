import AppKit
import Foundation

@MainActor
final class UsagePresenter: ObservableObject {
    @Published private(set) var state: UsageViewState = .idle
    @Published private(set) var isRefreshing = false

    private enum RefreshTrigger {
        case launch
        case popover
        case manual
        case automatic

        var isAutomatic: Bool {
            if case .automatic = self {
                return true
            }
            return false
        }
    }

    private var lastStarted: Date?
    private var lastSuccessfulSnapshot: UsageSnapshot?
    private var refreshSchedule = UsageRefreshSchedule()
    private var automaticTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var hasStarted = false

    init() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleWake()
            }
        }
    }

    var menuBarAppearance: MenuBarAppearance {
        UsageDisplay.menuBarAppearance(for: state)
    }

    func start() {
        guard !hasStarted else {
            return
        }
        hasStarted = true
        if applyVerificationSnapshotIfNeeded() {
            return
        }
        refresh(trigger: .launch)
    }

    func refreshFromPopover() {
        // MenuBarExtra can re-run onAppear on every state publish, which is not
        // a user opening the popover. After the first completed fetch, ignore it.
        switch state {
        case .idle, .loading:
            refresh(trigger: .popover)
        default:
            return
        }
    }

    func refreshNow() {
        refresh(trigger: .manual)
    }

    private func refresh(trigger: RefreshTrigger) {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return
        }
        if applyVerificationSnapshotIfNeeded() {
            return
        }
        if isRefreshing {
            return
        }
        if trigger == .popover,
           let lastStarted,
           Date().timeIntervalSince(lastStarted) < 3
        {
            return
        }

        let startedAt = Date()
        let resetBoundary = trigger.isAutomatic
            ? refreshSchedule.overdueResetBoundary(in: lastSuccessfulSnapshot, at: startedAt)
            : nil
        automaticTimer?.invalidate()
        automaticTimer = nil
        isRefreshing = true
        lastStarted = startedAt
        refreshSchedule.beginAttempt(at: startedAt, handling: resetBoundary)
        if shouldShowFirstLoadCopy {
            state = .loading
        }
        fputs("usage-state: \(shouldShowFirstLoadCopy ? "loading" : "refreshing")\n", stderr)

        Task {
            let result = await CodexUsageClient.fetchSnapshot()
            switch result {
            case .success(let snapshot):
                lastSuccessfulSnapshot = snapshot
                state = .available(snapshot)
                refreshSchedule.recordSuccess(snapshot)
                let constraining = snapshot.constrainingWindow
                fputs(
                    "usage-state: available plan=\(snapshot.planType ?? "none") windows=\(snapshot.windows.count) percent=\(constraining?.usedPercent.map(String.init) ?? "none") nearExhaustion=\(snapshot.emphasizesNearExhaustion)\n",
                    stderr
                )
            case .failure(let failure):
                if !trigger.isAutomatic || lastSuccessfulSnapshot == nil {
                    state = failure.viewState
                } else if let lastSuccessfulSnapshot {
                    state = .available(lastSuccessfulSnapshot)
                }
                fputs("usage-state: \(String(describing: failure))\n", stderr)
            }
            isRefreshing = false
            scheduleAutomaticRefresh()
        }
    }

    private func handleWake() {
        guard hasStarted, !applyVerificationSnapshotIfNeeded() else {
            return
        }
        let now = Date()
        guard refreshSchedule.shouldRefresh(snapshot: lastSuccessfulSnapshot, at: now) else {
            scheduleAutomaticRefresh()
            return
        }
        refresh(trigger: .automatic)
    }

    private func automaticTimerDidFire() {
        automaticTimer = nil
        guard refreshSchedule.shouldRefresh(snapshot: lastSuccessfulSnapshot, at: Date()) else {
            scheduleAutomaticRefresh()
            return
        }
        refresh(trigger: .automatic)
    }

    private func scheduleAutomaticRefresh() {
        automaticTimer?.invalidate()
        let now = Date()
        let nextDate = refreshSchedule.nextDate(snapshot: lastSuccessfulSnapshot, at: now)
        let timer = Timer(
            timeInterval: max(0.1, nextDate.timeIntervalSince(now)),
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.automaticTimerDidFire()
            }
        }
        automaticTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private var shouldShowFirstLoadCopy: Bool {
        switch state {
        case .idle, .loading:
            return true
        default:
            return false
        }
    }

    @discardableResult
    private func applyVerificationSnapshotIfNeeded() -> Bool {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["AI_USAGE_OBSERVATORY_SNAPSHOT"] {
        case "healthy":
            state = .available(.verificationHealthy)
            isRefreshing = false
            fputs("usage-state: available verification=healthy percent=72 nearExhaustion=false\n", stderr)
            return true
        case "exhausted":
            state = .available(.verificationExhausted)
            isRefreshing = false
            fputs("usage-state: available verification=exhausted percent=99 nearExhaustion=true\n", stderr)
            return true
        default:
            return false
        }
        #else
        return false
        #endif
    }
}

#if DEBUG
extension UsageSnapshot {
    /// Layout-only fixture for verifying the healthy presentation. Not a live quota read.
    static var verificationHealthy: UsageSnapshot {
        let fetchedAt = Date(timeIntervalSince1970: 1_767_000_000)
        return UsageSnapshot(
            planType: "plus",
            windows: [
                UsageWindow(
                    id: "codex-weekly",
                    title: "codex",
                    usedPercent: 72,
                    windowDurationMins: 10_080,
                    resetsAt: fetchedAt.addingTimeInterval(86_400)
                ),
            ],
            hasCredits: false,
            creditBalance: "0",
            rateLimitReachedType: nil,
            earnedResetCount: 0,
            fetchedAt: fetchedAt
        )
    }

    /// Layout-only fixture for verifying near-exhaustion. Matches the LAB-1 99% / null reached-type shape.
    static var verificationExhausted: UsageSnapshot {
        let fetchedAt = Date(timeIntervalSince1970: 1_767_000_000)
        return UsageSnapshot(
            planType: "plus",
            windows: [
                UsageWindow(
                    id: "codex-weekly",
                    title: "codex",
                    usedPercent: 99,
                    windowDurationMins: 10_080,
                    resetsAt: fetchedAt.addingTimeInterval(86_400)
                )
            ],
            hasCredits: false,
            creditBalance: "0",
            rateLimitReachedType: nil,
            earnedResetCount: 0,
            fetchedAt: fetchedAt
        )
    }
}
#endif
