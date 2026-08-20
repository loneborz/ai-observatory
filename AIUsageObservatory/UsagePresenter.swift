import Foundation

@MainActor
final class UsagePresenter: ObservableObject {
    @Published private(set) var state: UsageViewState = .idle
    @Published private(set) var isRefreshing = false

    private var lastStarted: Date?

    var menuBarAppearance: MenuBarAppearance {
        UsageDisplay.menuBarAppearance(for: state)
    }

    func start() {
        if applyVerificationSnapshotIfNeeded() {
            return
        }
        refresh(force: true)
    }

    func refreshFromPopover() {
        // MenuBarExtra can re-run onAppear on every state publish, which is not
        // a user opening the popover. After the first completed fetch, ignore it.
        switch state {
        case .idle, .loading:
            refresh(force: false)
        default:
            return
        }
    }

    func refreshNow() {
        refresh(force: true)
    }

    private func refresh(force: Bool) {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return
        }
        if applyVerificationSnapshotIfNeeded() {
            return
        }
        if isRefreshing {
            return
        }
        if !force, let lastStarted, Date().timeIntervalSince(lastStarted) < 3 {
            return
        }

        isRefreshing = true
        lastStarted = Date()
        if shouldShowFirstLoadCopy {
            state = .loading
        }
        fputs("usage-state: \(shouldShowFirstLoadCopy ? "loading" : "refreshing")\n", stderr)

        Task {
            let result = await CodexUsageClient.fetchSnapshot()
            switch result {
            case .success(let snapshot):
                state = .available(snapshot)
                let constraining = snapshot.constrainingWindow
                fputs(
                    "usage-state: available plan=\(snapshot.planType ?? "none") windows=\(snapshot.windows.count) percent=\(constraining?.usedPercent.map(String.init) ?? "none") nearExhaustion=\(snapshot.emphasizesNearExhaustion)\n",
                    stderr
                )
            case .failure(let failure):
                state = failure.viewState
                fputs("usage-state: \(String(describing: failure))\n", stderr)
            }
            isRefreshing = false
        }
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
        UsageSnapshot(
            planType: "plus",
            windows: [
                UsageWindow(
                    id: "codex-five-hour",
                    title: "codex",
                    usedPercent: 40,
                    windowDurationMins: 300,
                    resetsAt: Date().addingTimeInterval(3_600)
                ),
                UsageWindow(
                    id: "codex-weekly",
                    title: "codex",
                    usedPercent: 72,
                    windowDurationMins: 10_080,
                    resetsAt: Date().addingTimeInterval(86_400)
                ),
            ],
            hasCredits: false,
            creditBalance: "0",
            rateLimitReachedType: nil,
            earnedResetCount: 0,
            fetchedAt: Date()
        )
    }

    /// Layout-only fixture for verifying near-exhaustion. Matches the LAB-1 99% / null reached-type shape.
    static var verificationExhausted: UsageSnapshot {
        UsageSnapshot(
            planType: "plus",
            windows: [
                UsageWindow(
                    id: "codex-weekly",
                    title: "codex",
                    usedPercent: 99,
                    windowDurationMins: 10_080,
                    resetsAt: Date().addingTimeInterval(86_400)
                )
            ],
            hasCredits: false,
            creditBalance: "0",
            rateLimitReachedType: nil,
            earnedResetCount: 0,
            fetchedAt: Date()
        )
    }
}
#endif
