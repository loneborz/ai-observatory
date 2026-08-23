import Darwin
import Foundation
import os

enum AppServerProcessHost {
    private static let logger = Logger(
        subsystem: "nl.wavesweb.AIObservatory",
        category: "process"
    )

    static func withSession<T: Sendable>(
        executable: URL,
        timeout: Duration = .seconds(20),
        _ body: @escaping @Sendable (JSONRPCSession) async throws -> T
    ) async throws -> T {
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        let process = Process()
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        stderr.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        let session = JSONRPCSession(
            input: stdin.fileHandleForWriting,
            output: stdout.fileHandleForReading
        )

        do {
            try process.run()
        } catch {
            session.close()
            logger.error("Failed to spawn Codex app-server")
            throw UsageFetchFailure.spawnFailed
        }

        defer {
            session.close()
            stderr.fileHandleForReading.readabilityHandler = nil
            terminate(process)
        }

        do {
            return try await withDeadline(timeout) {
                try await body(session)
            }
        } catch is CancellationError {
            throw UsageFetchFailure.timeout
        } catch let failure as UsageFetchFailure {
            throw failure
        } catch {
            if !process.isRunning {
                throw UsageFetchFailure.crashed
            }
            throw UsageFetchFailure.rpcFailure
        }
    }

    private static func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(1)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
    }

    private static func withDeadline<T: Sendable>(
        _ timeout: Duration,
        _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let box = ResumeBox<T>()
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                do {
                    let value = try await work()
                    box.resume(continuation, .success(value))
                } catch {
                    box.resume(continuation, .failure(error))
                }
            }
            let seconds = Double(timeout.components.seconds)
                + Double(timeout.components.attoseconds) / 1_000_000_000_000_000_000
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                box.resume(continuation, .failure(UsageFetchFailure.timeout))
            }
        }
    }
}

private final class ResumeBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func resume(_ continuation: CheckedContinuation<T, Error>, _ result: Result<T, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        continuation.resume(with: result)
    }
}
