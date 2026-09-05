import Foundation

final class CodexUsageCollector: @unchecked Sendable {
    enum CollectorError: LocalizedError {
        case missingDirectory(String)
        case unreadableDirectory(String)
        case malformedRecord(file: String, line: Int, reason: String)
        case invalidToken(file: String, field: String)

        var errorDescription: String? {
            switch self {
            case .missingDirectory(let path):
                "Codex sessions directory does not exist: \(path)"
            case .unreadableDirectory(let path):
                "Codex sessions directory cannot be read: \(path)"
            case .malformedRecord(let file, let line, let reason):
                "Codex session record is invalid at \(file):\(line): \(reason)"
            case .invalidToken(let file, let field):
                "Codex session \(file) contains an invalid non-negative integer for \(field)."
            }
        }
    }

    private struct CacheEntry {
        let fileSize: Int
        let modificationDate: Date
        let sample: UsageSample?
    }

    let sessionsDirectory: URL
    private var cache: [URL: CacheEntry] = [:]

    init(sessionsDirectory: URL) {
        self.sessionsDirectory = sessionsDirectory
    }

    func collect(since startDate: Date) throws -> [UsageSample] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sessionsDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw CollectorError.missingDirectory(sessionsDirectory.path)
        }

        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            throw CollectorError.unreadableDirectory(sessionsDirectory.path)
        }

        var samples: [UsageSample] = []
        var discoveredFiles: Set<URL> = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            discoveredFiles.insert(fileURL)
            let values = try fileURL.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true,
                  let modifiedAt = values.contentModificationDate,
                  let fileSize = values.fileSize,
                  modifiedAt >= startDate
            else { continue }

            let sample: UsageSample?
            if let cached = cache[fileURL],
               cached.fileSize == fileSize,
               cached.modificationDate == modifiedAt {
                sample = cached.sample
            } else {
                sample = try parseSession(at: fileURL, fallbackTimestamp: modifiedAt)
                cache[fileURL] = CacheEntry(
                    fileSize: fileSize,
                    modificationDate: modifiedAt,
                    sample: sample
                )
            }
            if let sample {
                samples.append(sample)
            }
        }
        cache = cache.filter { discoveredFiles.contains($0.key) }
        return samples.sorted { $0.timestamp > $1.timestamp }
    }

    func parseSession(at fileURL: URL, fallbackTimestamp: Date? = nil) throws -> UsageSample? {
        var sessionID: String?
        var workspace: String?
        var model: String?
        var latestUsage: [String: Any]?
        var latestTimestamp: Date?

        try forEachLine(at: fileURL) { line, lineNumber in
            guard !line.isEmpty else { return }
            let record: [String: Any]
            do {
                guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    throw CollectorError.malformedRecord(
                        file: fileURL.path,
                        line: lineNumber,
                        reason: "record must be a JSON object"
                    )
                }
                record = object
            } catch let error as CollectorError {
                throw error
            } catch {
                throw CollectorError.malformedRecord(
                    file: fileURL.path,
                    line: lineNumber,
                    reason: error.localizedDescription
                )
            }

            guard let payload = record["payload"] as? [String: Any] else { return }
            switch record["type"] as? String {
            case "session_meta":
                sessionID = nonEmptyString(payload["id"]) ?? nonEmptyString(payload["session_id"]) ?? sessionID
                workspace = nonEmptyString(payload["cwd"]) ?? workspace
            case "turn_context":
                model = nonEmptyString(payload["model"]) ?? model
            case "event_msg" where payload["type"] as? String == "token_count":
                guard let info = payload["info"] as? [String: Any],
                      let totals = info["total_token_usage"] as? [String: Any]
                else { return }
                latestUsage = totals
                if let value = nonEmptyString(record["timestamp"]) {
                    latestTimestamp = Self.parseTimestamp(value)
                    if latestTimestamp == nil {
                        throw CollectorError.malformedRecord(
                            file: fileURL.path,
                            line: lineNumber,
                            reason: "timestamp is not ISO-8601"
                        )
                    }
                }
            default:
                return
            }
        }

        guard let latestUsage else { return nil }
        let input = try token(latestUsage["input_tokens"], field: "input_tokens", file: fileURL.path)
        let cached = try token(
            latestUsage["cached_input_tokens"] ?? 0,
            field: "cached_input_tokens",
            file: fileURL.path
        )
        let output = try token(latestUsage["output_tokens"], field: "output_tokens", file: fileURL.path)
        let total = try token(
            latestUsage["total_tokens"] ?? input + output,
            field: "total_tokens",
            file: fileURL.path
        )
        guard total >= input + output else {
            throw CollectorError.malformedRecord(
                file: fileURL.path,
                line: 0,
                reason: "total_tokens cannot be smaller than input_tokens + output_tokens"
            )
        }

        return UsageSample(
            provider: .codex,
            accountOrWorkspace: workspace,
            model: model,
            sessionID: sessionID ?? fileURL.deletingPathExtension().lastPathComponent,
            inputTokens: input,
            cachedInputTokens: cached,
            outputTokens: output,
            totalTokens: total,
            timestamp: latestTimestamp ?? fallbackTimestamp ?? Date(),
            sourceType: .localStructuredLog,
            sourceConfidence: .verified
        )
    }

    private func token(_ value: Any?, field: String, file: String) throws -> Int {
        guard let value = value as? Int, value >= 0 else {
            throw CollectorError.invalidToken(file: file, field: field)
        }
        return value
    }

    private func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty else { return nil }
        return value
    }

    private func forEachLine(
        at fileURL: URL,
        _ body: (Data, Int) throws -> Void
    ) throws {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: fileURL)
        } catch {
            throw CollectorError.malformedRecord(
                file: fileURL.path,
                line: 0,
                reason: error.localizedDescription
            )
        }
        defer { try? handle.close() }

        var buffer = Data()
        var lineNumber = 0

        do {
            while let chunk = try handle.read(upToCount: 256 * 1024), !chunk.isEmpty {
                buffer.append(chunk)
                var lineStart = buffer.startIndex

                while let newline = buffer[lineStart...].firstIndex(of: 0x0A) {
                    lineNumber += 1
                    try body(Data(buffer[lineStart..<newline]), lineNumber)
                    lineStart = buffer.index(after: newline)
                }

                if lineStart != buffer.startIndex {
                    buffer.removeSubrange(buffer.startIndex..<lineStart)
                }
            }

            if !buffer.isEmpty {
                lineNumber += 1
                try body(buffer, lineNumber)
            }
        } catch let error as CollectorError {
            throw error
        } catch {
            throw CollectorError.malformedRecord(
                file: fileURL.path,
                line: lineNumber,
                reason: error.localizedDescription
            )
        }
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
