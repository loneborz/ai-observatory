import Foundation
import os

enum CodexUsageClient {
    private static let logger = Logger(
        subsystem: "nl.wavesweb.AIUsageObservatory",
        category: "usage"
    )

    static func fetchSnapshot() async -> Result<UsageSnapshot, UsageFetchFailure> {
        await Task.detached(priority: .userInitiated) {
            await fetchSnapshotOffMain()
        }.value
    }

    private static func fetchSnapshotOffMain() async -> Result<UsageSnapshot, UsageFetchFailure> {
        guard let executable = CodexCLILocator.locate() else {
            logger.error("Codex CLI not found")
            return .failure(.cliMissing)
        }

        do {
            let snapshot = try await AppServerProcessHost.withSession(executable: executable) { session in
                try await readUsage(using: session)
            }
            logger.info("Fetched plan=\(snapshot.planType ?? "none", privacy: .public) windows=\(snapshot.windows.count, privacy: .public) percent=\(snapshot.windows.first?.usedPercent ?? -1, privacy: .public)")
            return .success(snapshot)
        } catch let failure as UsageFetchFailure {
            logger.error("Usage fetch failed: \(String(describing: failure), privacy: .public)")
            return .failure(failure)
        } catch {
            logger.error("Usage fetch failed with unexpected error")
            return .failure(.rpcFailure)
        }
    }

    private static func readUsage(using session: JSONRPCSession) async throws -> UsageSnapshot {
        _ = try await session.request(
            "initialize",
            params: [
                "clientInfo": [
                    "name": "ai-usage-observatory",
                    "title": "AI Usage Observatory",
                    "version": "0.1.0",
                ],
                "capabilities": [
                    "experimentalApi": true,
                ],
            ]
        )
        try session.notify("initialized")

        let accountResult = try await requestResult(session, method: "account/read", params: ["refreshToken": false])
        let account = try decode(AccountReadResult.self, from: accountResult)
        try ensureChatGPTAccount(account)

        let limitsResult: Any
        do {
            limitsResult = try await requestResult(session, method: "account/rateLimits/read")
        } catch let error as JSONRPCError {
            throw classifyRPCError(error.message)
        }
        let limits = try decode(RateLimitsReadResult.self, from: limitsResult)
        return mapSnapshot(account: account, limits: limits)
    }

    private static func requestResult(
        _ session: JSONRPCSession,
        method: String,
        params: [String: Any]? = nil
    ) async throws -> Any {
        do {
            return try await session.request(method, params: params)
        } catch let error as JSONRPCError {
            throw classifyRPCError(error.message)
        }
    }

    private static func ensureChatGPTAccount(_ account: AccountReadResult) throws {
        guard let info = account.account else {
            throw UsageFetchFailure.loggedOut
        }
        guard info.type == "chatgpt" else {
            throw UsageFetchFailure.loggedOut
        }
    }

    private static func classifyRPCError(_ message: String) -> UsageFetchFailure {
        let lower = message.lowercased()
        if lower.contains("not logged")
            || lower.contains("unauthoriz")
            || lower.contains("not authenticated")
            || lower.contains("authentication")
            || lower.contains("auth required")
            || lower.contains("login required")
            || lower.contains("sign in")
        {
            return .loggedOut
        }
        if lower.contains("network")
            || lower.contains("offline")
            || lower.contains("connection")
            || lower.contains("unreachable")
            || lower.contains("timed out")
            || lower.contains("timeout")
            || lower.contains("temporarily unavailable")
        {
            return .unavailable
        }
        return .rpcFailure
    }

    private static func decode<T: Decodable>(_ type: T.Type, from result: Any) throws -> T {
        guard JSONSerialization.isValidJSONObject(result) else {
            throw UsageFetchFailure.malformed
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: result)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw UsageFetchFailure.malformed
        }
    }

    private static func mapSnapshot(account: AccountReadResult, limits: RateLimitsReadResult) -> UsageSnapshot {
        var collected: [UsageWindow] = []
        if let byLimitID = limits.rateLimitsByLimitId, !byLimitID.isEmpty {
            for (limitID, snapshot) in byLimitID.sorted(by: { $0.key < $1.key }) {
                collected.append(contentsOf: windows(from: snapshot, fallbackID: limitID))
            }
        } else if let snapshot = limits.rateLimits {
            collected.append(contentsOf: windows(from: snapshot, fallbackID: snapshot.limitId ?? "codex"))
        }

        let credits = limits.rateLimits?.credits
        return UsageSnapshot(
            planType: account.account?.planType ?? limits.rateLimits?.planType,
            windows: collected,
            hasCredits: credits?.hasCredits,
            creditBalance: credits?.balance,
            rateLimitReachedType: limits.rateLimits?.rateLimitReachedType,
            earnedResetCount: limits.rateLimitResetCredits?.availableCount,
            fetchedAt: Date()
        )
    }

    private static func windows(from snapshot: RateLimitSnapshot, fallbackID: String) -> [UsageWindow] {
        var result: [UsageWindow] = []
        if let primary = snapshot.primary {
            result.append(
                UsageWindow(
                    id: "\(fallbackID)-primary",
                    title: windowTitle(snapshot: snapshot, fallbackID: fallbackID, suffix: snapshot.secondary == nil ? nil : "primary"),
                    usedPercent: primary.usedPercent.map(Int.init),
                    windowDurationMins: primary.windowDurationMins,
                    resetsAt: primary.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                )
            )
        }
        if let secondary = snapshot.secondary {
            result.append(
                UsageWindow(
                    id: "\(fallbackID)-secondary",
                    title: windowTitle(snapshot: snapshot, fallbackID: fallbackID, suffix: "secondary"),
                    usedPercent: secondary.usedPercent.map(Int.init),
                    windowDurationMins: secondary.windowDurationMins,
                    resetsAt: secondary.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                )
            )
        }
        return result
    }

    private static func windowTitle(snapshot: RateLimitSnapshot, fallbackID: String, suffix: String?) -> String {
        let base = snapshot.limitName?.nilIfEmpty ?? snapshot.limitId ?? fallbackID
        if let suffix {
            return "\(base) \(suffix)"
        }
        return base
    }
}

private struct AccountReadResult: Decodable {
    var account: AccountInfo?
    var requiresOpenaiAuth: Bool?
}

private struct AccountInfo: Decodable {
    var type: String
    var planType: String?
}

private struct RateLimitsReadResult: Decodable {
    var rateLimits: RateLimitSnapshot?
    var rateLimitsByLimitId: [String: RateLimitSnapshot]?
    var rateLimitResetCredits: RateLimitResetCredits?
}

private struct RateLimitSnapshot: Decodable {
    var limitId: String?
    var limitName: String?
    var primary: RateLimitWindow?
    var secondary: RateLimitWindow?
    var credits: CreditsSnapshot?
    var planType: String?
    var rateLimitReachedType: String?
}

private struct RateLimitWindow: Decodable {
    var usedPercent: Double?
    var windowDurationMins: Int?
    var resetsAt: Int?

    enum CodingKeys: String, CodingKey {
        case usedPercent
        case windowDurationMins
        case resetsAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercent = Self.decodeDouble(container, forKey: .usedPercent)
        windowDurationMins = Self.decodeInt(container, forKey: .windowDurationMins)
        resetsAt = Self.decodeInt(container, forKey: .resetsAt)
    }

    private static func decodeDouble(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Double? {
        if let value = try? container.decode(Double.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Int.self, forKey: key) {
            return Double(value)
        }
        return nil
    }

    private static func decodeInt(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Int? {
        if let value = try? container.decode(Int.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Double.self, forKey: key) {
            return Int(value)
        }
        return nil
    }
}

private struct CreditsSnapshot: Decodable {
    var hasCredits: Bool?
    var balance: String?
}

private struct RateLimitResetCredits: Decodable {
    var availableCount: Int?

    enum CodingKeys: String, CodingKey {
        case availableCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decode(Int.self, forKey: .availableCount) {
            availableCount = value
        } else if let value = try? container.decode(Double.self, forKey: .availableCount) {
            availableCount = Int(value)
        } else {
            availableCount = nil
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
