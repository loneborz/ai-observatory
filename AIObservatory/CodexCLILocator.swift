import Foundation

enum CodexCLILocator {
    static let chatGPTBundledCLI = URL(
        fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"
    )

    /// Resolves a Codex executable without reading `~/.codex`.
    /// Order: optional verification override, `codex` on PATH, then ChatGPT.app.
    static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileExists: (URL) -> Bool = { FileManager.default.isExecutableFile(atPath: $0.path) }
    ) -> URL? {
        if let override = environment["AI_OBSERVATORY_CODEX"] {
            if override == "missing" {
                return nil
            }
            let url = URL(fileURLWithPath: override)
            return fileExists(url) ? url : nil
        }

        if let fromPath = locateOnPATH(environment["PATH"] ?? "", fileExists: fileExists) {
            return fromPath
        }

        return fileExists(chatGPTBundledCLI) ? chatGPTBundledCLI : nil
    }

    private static func locateOnPATH(_ path: String, fileExists: (URL) -> Bool) -> URL? {
        let directories = path.split(separator: ":").map(String.init)
        for directory in directories {
            let candidate = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent("codex")
            if fileExists(candidate) {
                return candidate
            }
        }
        return nil
    }
}
