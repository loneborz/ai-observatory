import Foundation

struct UsageSnapshot: Equatable, Sendable {
    var planType: String?
    var windows: [UsageWindow]
    var hasCredits: Bool?
    var creditBalance: String?
    var rateLimitReachedType: String?
    var earnedResetCount: Int?
    var fetchedAt: Date
}

struct UsageWindow: Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var usedPercent: Int?
    var windowDurationMins: Int?
    var resetsAt: Date?
}

enum UsageViewState: Equatable {
    case idle
    case loading
    case available(UsageSnapshot)
    case loggedOut(String)
    case unavailable(String)
    case error(String)
}

enum UsageFetchFailure: Error, Equatable, Sendable {
    case cliMissing
    case spawnFailed
    case loggedOut
    case unavailable
    case rpcFailure
    case timeout
    case crashed
    case malformed

    var viewState: UsageViewState {
        switch self {
        case .cliMissing:
            return .unavailable("Codex CLI not found.")
        case .spawnFailed:
            return .unavailable("Couldn't start Codex.")
        case .loggedOut:
            return .loggedOut("Not signed in. Sign in with Codex or ChatGPT.")
        case .unavailable:
            return .unavailable("Can't reach ChatGPT right now.")
        case .rpcFailure, .timeout, .crashed, .malformed:
            return .error("Failed to read usage. Refresh later.")
        }
    }
}
