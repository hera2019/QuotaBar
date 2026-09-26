import Foundation

/// Reads GPT (Codex) usage through the `codex app-server` bundled with the ChatGPT desktop app.
enum CodexSource {
    static let candidates: [String] = {
        let appRoots = ["/Applications", NSHomeDirectory() + "/Applications"]
            .flatMap { root in [root + "/ChatGPT.app", root + "/Codex.app"] }
        let bundled = appRoots.flatMap { app in
            [app + "/Contents/Resources/codex-cli/bin/codex",
             app + "/Contents/Resources/codex"]
        }
        return bundled + ["/opt/homebrew/bin/codex", "/usr/local/bin/codex",
                          NSHomeDirectory() + "/.local/bin/codex"]
    }()

    static func fetch(timeout: TimeInterval = 20, completion: @escaping (Result<ProviderUsage, SourceError>) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let result = fetchSync(timeout: timeout)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func fetchSync(timeout: TimeInterval) -> Result<ProviderUsage, SourceError> {
        guard let exe = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return .failure(.notFound)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = ["app-server", "--stdio"]
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return .failure(.launchFailed) }

        let requests = [
            #"{"method":"initialize","id":0,"params":{"clientInfo":{"name":"quotabar","title":"QuotaBar","version":"1.0.2"}}}"#,
            #"{"method":"initialized","params":{}}"#,
            #"{"method":"account/rateLimits/read","id":1,"params":{"excludeResetCreditDetails":true}}"#,
        ]
        stdin.fileHandleForWriting.write((requests.joined(separator: "\n") + "\n").data(using: .utf8)!)

        // On timeout, kill the process; the blocking read below then returns.
        var timedOut = false
        let killer = DispatchWorkItem { timedOut = true; process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        defer {
            killer.cancel()
            try? stdin.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
        }

        var buffer = Data()
        var awaitingLegacyResponse = false
        let reader = stdout.fileHandleForReading
        // availableData returns whatever has arrived; read(upToCount:) would wait for the full count.
        while case let chunk = reader.availableData, !chunk.isEmpty {
            buffer.append(chunk)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<nl]
                buffer.removeSubrange(buffer.startIndex...nl)
                guard let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                      let id = (obj["id"] as? NSNumber)?.intValue else { continue }
                if id == 1, let error = obj["error"] as? [String: Any],
                   let code = (error["code"] as? NSNumber)?.intValue,
                   code == -32600 || code == -32602 {
                    // Older app-servers accept only a request without params.
                    let legacy = #"{"method":"account/rateLimits/read","id":2}"# + "\n"
                    stdin.fileHandleForWriting.write(Data(legacy.utf8))
                    awaitingLegacyResponse = true
                    continue
                }
                guard id == (awaitingLegacyResponse ? 2 : 1) else { continue }
                return parse(obj)
            }
        }
        return .failure(timedOut ? .timedOut : .malformed)
    }

    static func parse(_ obj: [String: Any]) -> Result<ProviderUsage, SourceError> {
        if let err = obj["error"] as? [String: Any] {
            return .failure(.message((err["message"] as? String) ?? L10n.codexError))
        }
        guard let result = obj["result"] as? [String: Any] else { return .failure(.malformed) }
        let limits = ((result["rateLimitsByLimitId"] as? [String: Any])?["codex"] as? [String: Any])
            ?? (result["rateLimits"] as? [String: Any])
        guard let limits else { return .failure(.malformed) }

        // Either window may be null (e.g. Plus has only a weekly limit). Classify by duration, not position.
        var usage = ProviderUsage(fiveHour: nil, weekly: nil, updatedAt: Date())
        for (key, fallback) in [("primary", Span.fiveHour), ("secondary", Span.weekly)] {
            guard let w = limits[key] as? [String: Any],
                  let used = (w["usedPercent"] as? NSNumber)?.doubleValue else { continue }
            let reset = (w["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            let window = LimitWindow(usedPercent: used, resetsAt: reset)
            let span = (w["windowDurationMins"] as? NSNumber).map { $0.intValue <= 24 * 60 ? Span.fiveHour : .weekly } ?? fallback
            switch span {
            case .fiveHour: usage.fiveHour = window
            case .weekly: usage.weekly = window
            }
        }
        if usage.fiveHour == nil && usage.weekly == nil { return .failure(.malformed) }
        return .success(usage)
    }
}
