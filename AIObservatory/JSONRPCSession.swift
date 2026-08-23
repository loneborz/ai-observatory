import Darwin
import Foundation

struct JSONRPCError: Error {
    var message: String
}

/// Newline-delimited JSON-RPC 2.0 without a `jsonrpc` field, matching Codex app-server stdio.
final class JSONRPCSession: @unchecked Sendable {
    private let input: FileHandle
    private let output: FileHandle
    private let queue = DispatchQueue(label: "nl.wavesweb.AIObservatory.rpc")
    private var buffer = Data()
    private var queuedLines: [String] = []
    private var waiters: [CheckedContinuation<String?, Error>] = []
    private var nextID = 1
    private var finished = false

    init(input: FileHandle, output: FileHandle) {
        self.input = input
        self.output = output
        output.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            self?.queue.async {
                self?.consume(chunk)
            }
        }
    }

    func close() {
        queue.sync {
            finished = true
            output.readabilityHandler = nil
            failWaiters()
        }
        try? input.close()
    }

    func notify(_ method: String, params: [String: Any]? = nil) throws {
        var message: [String: Any] = ["method": method]
        if let params {
            message["params"] = params
        }
        try write(message)
    }

    func request(_ method: String, params: [String: Any]? = nil) async throws -> Any {
        let id: Int = queue.sync {
            let value = nextID
            nextID += 1
            return value
        }
        var message: [String: Any] = ["id": id, "method": method]
        if let params {
            message["params"] = params
        }
        try write(message)

        while let line = try await readLine() {
            guard let object = decodeObject(line) else {
                continue
            }
            guard idsMatch(object["id"], id) else {
                continue
            }
            if let error = object["error"] as? [String: Any] {
                throw JSONRPCError(message: (error["message"] as? String) ?? "JSON-RPC error")
            }
            if let result = object["result"] {
                return result
            }
            throw UsageFetchFailure.malformed
        }

        throw UsageFetchFailure.crashed
    }

    private func write(_ message: [String: Any]) throws {
        var payload = try JSONSerialization.data(withJSONObject: message)
        payload.append(0x0A)
        let fd = input.fileDescriptor
        let written: Int = payload.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return -1 }
            return Darwin.write(fd, base, raw.count)
        }
        if written != payload.count {
            throw UsageFetchFailure.crashed
        }
    }

    private func readLine() async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if !self.queuedLines.isEmpty {
                    continuation.resume(returning: self.queuedLines.removeFirst())
                } else if self.finished {
                    continuation.resume(returning: nil)
                } else {
                    self.waiters.append(continuation)
                }
            }
        }
    }

    private func consume(_ chunk: Data) {
        if chunk.isEmpty {
            finished = true
            failWaiters()
            return
        }
        buffer.append(chunk)
        while let line = popLine() {
            if waiters.isEmpty {
                queuedLines.append(line)
            } else {
                let waiter = waiters.removeFirst()
                waiter.resume(returning: line)
            }
        }
    }

    private func failWaiters() {
        let remaining = waiters
        waiters.removeAll()
        for waiter in remaining {
            waiter.resume(returning: nil)
        }
    }

    private func popLine() -> String? {
        guard let newline = buffer.firstIndex(of: 0x0A) else {
            return nil
        }
        let lineData = buffer.subdata(in: buffer.startIndex..<newline)
        buffer.removeSubrange(buffer.startIndex..<buffer.index(after: newline))
        return String(data: lineData, encoding: .utf8) ?? ""
    }

    private func decodeObject(_ line: String) -> [String: Any]? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func idsMatch(_ value: Any?, _ expected: Int) -> Bool {
        if let number = value as? Int {
            return number == expected
        }
        if let number = value as? NSNumber {
            return number.intValue == expected
        }
        if let text = value as? String, let number = Int(text) {
            return number == expected
        }
        return false
    }
}
