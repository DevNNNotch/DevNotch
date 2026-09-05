import Foundation

struct CodexActivityMonitor: Sendable {
    enum MonitorError: LocalizedError {
        case missingDirectory(String)
        case unreadableDirectory(String)
        case unreadableFile(String, String)
        case truncatedFile(String)
        case malformedRecord(file: String, byteOffset: UInt64, reason: String)
        case missingTaskTitle(file: String, turnID: String)
        case missingCompletionPreview(file: String, turnID: String)
        case mismatchedCompletion(file: String, expected: String, received: String)

        var errorDescription: String? {
            switch self {
            case .missingDirectory(let path):
                "Codex sessions directory does not exist: \(path)"
            case .unreadableDirectory(let path):
                "Codex sessions directory cannot be read: \(path)"
            case .unreadableFile(let path, let reason):
                "Codex session cannot be read at \(path): \(reason)"
            case .truncatedFile(let path):
                "Codex session was truncated while being monitored: \(path)"
            case .malformedRecord(let file, let byteOffset, let reason):
                "Codex activity record is invalid at \(file), byte \(byteOffset): \(reason)"
            case .missingTaskTitle(let file, let turnID):
                "Codex task \(turnID) completed without a user task title in \(file)."
            case .missingCompletionPreview(let file, let turnID):
                "Codex task \(turnID) completed without last_agent_message in \(file)."
            case .mismatchedCompletion(let file, let expected, let received):
                "Codex task completion in \(file) does not match the active turn. Expected \(expected), received \(received)."
            }
        }
    }

    let sessionsDirectory: URL
    let pollInterval: Duration
    let discoveryInterval: TimeInterval

    init(
        sessionsDirectory: URL,
        pollInterval: Duration = .milliseconds(500),
        discoveryInterval: TimeInterval = 2
    ) {
        self.sessionsDirectory = sessionsDirectory
        self.pollInterval = pollInterval
        self.discoveryInterval = discoveryInterval
    }

    func run(
        onUpdate: @escaping @Sendable (CodexActivityUpdate) async -> Void
    ) async throws {
        var scanner = CodexActivityScanner(
            sessionsDirectory: sessionsDirectory,
            discoveryInterval: discoveryInterval,
            completionCutoff: Date()
        )

        for update in try scanner.scan(forceDiscovery: true) {
            await onUpdate(update)
        }

        while !Task.isCancelled {
            try await Task.sleep(for: pollInterval)
            for update in try scanner.scan() {
                await onUpdate(update)
            }
        }
    }
}

struct CodexActivityLogParser {
    private(set) var sessionID: String
    private(set) var activeTask: CodexTaskActivity?
    private(set) var hasSeenLifecycleEvent = false
    private(set) var hasSeenTaskStart = false

    init(fileIdentifier: String) {
        sessionID = fileIdentifier
    }

    mutating func consume(
        _ line: Data,
        file: URL,
        byteOffset: UInt64,
        completionCutoff: Date
    ) throws -> CodexTaskCompletion? {
        guard !line.isEmpty else { return nil }

        let record: [String: Any]
        do {
            guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                throw CodexActivityMonitor.MonitorError.malformedRecord(
                    file: file.path,
                    byteOffset: byteOffset,
                    reason: "record must be a JSON object"
                )
            }
            record = object
        } catch let error as CodexActivityMonitor.MonitorError {
            throw error
        } catch {
            throw CodexActivityMonitor.MonitorError.malformedRecord(
                file: file.path,
                byteOffset: byteOffset,
                reason: error.localizedDescription
            )
        }

        guard let payload = record["payload"] as? [String: Any] else { return nil }
        let recordType = record["type"] as? String
        let payloadType = payload["type"] as? String

        if recordType == "session_meta" {
            if let identifier = nonEmptyString(payload["id"]) ?? nonEmptyString(payload["session_id"]) {
                sessionID = identifier
            }
            return nil
        }

        if recordType == "response_item", payloadType == "message", payload["role"] as? String == "user" {
            guard var task = activeTask,
                  let content = payload["content"] as? [[String: Any]]
            else { return nil }

            let text = content.compactMap { item -> String? in
                guard item["type"] as? String == "input_text" else { return nil }
                return nonEmptyString(item["text"])
            }.joined(separator: "\n")

            if let title = CodexTaskText.taskTitle(from: text) {
                task = CodexTaskActivity(
                    turnID: task.turnID,
                    sessionID: sessionID,
                    title: title,
                    startedAt: task.startedAt
                )
                activeTask = task
            }
            return nil
        }

        guard recordType == "event_msg" else { return nil }
        switch payloadType {
        case "task_started":
            hasSeenLifecycleEvent = true
            hasSeenTaskStart = true
            let turnID = try requiredString(payload["turn_id"], field: "turn_id", file: file, byteOffset: byteOffset)
            let timestamp = try requiredTimestamp(
                payload["started_at"] ?? record["timestamp"],
                field: "started_at",
                file: file,
                byteOffset: byteOffset
            )
            activeTask = CodexTaskActivity(
                turnID: turnID,
                sessionID: sessionID,
                title: "",
                startedAt: timestamp
            )
            return nil

        case "turn_aborted":
            hasSeenLifecycleEvent = true
            if let receivedTurnID = nonEmptyString(payload["turn_id"]),
               let activeTask,
               receivedTurnID != activeTask.turnID {
                throw CodexActivityMonitor.MonitorError.mismatchedCompletion(
                    file: file.path,
                    expected: activeTask.turnID,
                    received: receivedTurnID
                )
            }
            activeTask = nil
            return nil

        case "task_complete":
            hasSeenLifecycleEvent = true
            let turnID = try requiredString(payload["turn_id"], field: "turn_id", file: file, byteOffset: byteOffset)
            let completedAt = try requiredTimestamp(
                payload["completed_at"] ?? record["timestamp"],
                field: "completed_at",
                file: file,
                byteOffset: byteOffset
            )

            guard completedAt >= completionCutoff else {
                activeTask = nil
                return nil
            }
            guard let task = activeTask else {
                throw CodexActivityMonitor.MonitorError.missingTaskTitle(file: file.path, turnID: turnID)
            }
            guard task.turnID == turnID else {
                throw CodexActivityMonitor.MonitorError.mismatchedCompletion(
                    file: file.path,
                    expected: task.turnID,
                    received: turnID
                )
            }
            guard !task.title.isEmpty else {
                throw CodexActivityMonitor.MonitorError.missingTaskTitle(file: file.path, turnID: turnID)
            }
            guard let message = nonEmptyString(payload["last_agent_message"]) else {
                throw CodexActivityMonitor.MonitorError.missingCompletionPreview(file: file.path, turnID: turnID)
            }

            activeTask = nil
            return CodexTaskCompletion(
                turnID: turnID,
                sessionID: task.sessionID,
                title: task.title,
                preview: CodexTaskText.responsePreview(from: message),
                completedAt: completedAt
            )

        default:
            return nil
        }
    }

    private func requiredString(
        _ value: Any?,
        field: String,
        file: URL,
        byteOffset: UInt64
    ) throws -> String {
        guard let value = nonEmptyString(value) else {
            throw CodexActivityMonitor.MonitorError.malformedRecord(
                file: file.path,
                byteOffset: byteOffset,
                reason: "\(field) must be a non-empty string"
            )
        }
        return value
    }

    private func requiredTimestamp(
        _ value: Any?,
        field: String,
        file: URL,
        byteOffset: UInt64
    ) throws -> Date {
        if let value = nonEmptyString(value), let date = Self.parseTimestamp(value) {
            return date
        }
        if let value = value as? NSNumber {
            let seconds = value.doubleValue
            if seconds.isFinite, seconds >= 0 {
                return Date(timeIntervalSince1970: seconds)
            }
        }
        throw CodexActivityMonitor.MonitorError.malformedRecord(
            file: file.path,
            byteOffset: byteOffset,
            reason: "\(field) must be an ISO-8601 timestamp or Unix time in seconds"
        )
    }

    private func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return value
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

enum CodexTaskText {
    static func taskTitle(from text: String) -> String? {
        let requestMarker = "## My request:"
        let request = text.range(of: requestMarker, options: .backwards).map {
            String(text[$0.upperBound...])
        } ?? text

        let visibleLines = request.components(separatedBy: .newlines).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty
                && !trimmed.hasPrefix("<image ")
                && trimmed != "</image>"
        }
        let normalized = visibleLines
            .joined(separator: " ")
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(180))
    }

    static func responsePreview(from text: String) -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(normalized.prefix(800))
    }
}

struct CodexActivityScanner {
    private struct FileCursor {
        var offset: UInt64
        var pending = Data()
        var parser: CodexActivityLogParser
    }

    private struct SessionFile {
        let url: URL
        let size: UInt64
        let modificationDate: Date
    }

    let sessionsDirectory: URL
    let discoveryInterval: TimeInterval
    let completionCutoff: Date
    private var cursors: [URL: FileCursor] = [:]
    private var nextDiscovery = Date.distantPast
    private var lastPublishedTasks: [CodexTaskActivity] = []

    init(sessionsDirectory: URL, discoveryInterval: TimeInterval, completionCutoff: Date) {
        self.sessionsDirectory = sessionsDirectory
        self.discoveryInterval = discoveryInterval
        self.completionCutoff = completionCutoff
    }

    mutating func scan(forceDiscovery: Bool = false) throws -> [CodexActivityUpdate] {
        var updates: [CodexActivityUpdate] = []
        let now = Date()

        if forceDiscovery || now >= nextDiscovery {
            for file in try recentSessionFiles(since: now.addingTimeInterval(-604_800)) where cursors[file.url] == nil {
                let result = try bootstrap(file)
                cursors[file.url] = result.cursor
                updates.append(contentsOf: result.completions.map(CodexActivityUpdate.completed))
            }
            nextDiscovery = now.addingTimeInterval(discoveryInterval)
        }

        for url in cursors.keys.sorted(by: { $0.path < $1.path }) {
            guard var cursor = cursors[url] else { continue }
            guard FileManager.default.fileExists(atPath: url.path) else {
                cursors.removeValue(forKey: url)
                continue
            }

            let size = try fileSize(at: url)
            guard size >= cursor.offset else {
                throw CodexActivityMonitor.MonitorError.truncatedFile(url.path)
            }
            if size > cursor.offset {
                let chunk = try read(file: url, from: cursor.offset)
                cursor.offset += UInt64(chunk.count)
                cursor.pending.append(chunk)
                let completions = try consumeCompleteLines(in: &cursor, file: url)
                updates.append(contentsOf: completions.map(CodexActivityUpdate.completed))
                cursors[url] = cursor
            }
        }

        let activeTasks = cursors.values.compactMap(\.parser.activeTask).sorted {
            if $0.startedAt == $1.startedAt { return $0.turnID < $1.turnID }
            return $0.startedAt < $1.startedAt
        }
        if activeTasks != lastPublishedTasks {
            lastPublishedTasks = activeTasks
            updates.append(.runningTasks(activeTasks))
        }
        return updates
    }

    private func recentSessionFiles(since startDate: Date) throws -> [SessionFile] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sessionsDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw CodexActivityMonitor.MonitorError.missingDirectory(sessionsDirectory.path)
        }

        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        var traversalError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles],
            errorHandler: { _, error in
                traversalError = error
                return false
            }
        ) else {
            throw CodexActivityMonitor.MonitorError.unreadableDirectory(sessionsDirectory.path)
        }

        var files: [SessionFile] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true,
                  let modificationDate = values.contentModificationDate,
                  let size = values.fileSize,
                  modificationDate >= startDate
            else { continue }
            files.append(SessionFile(url: url, size: UInt64(size), modificationDate: modificationDate))
        }
        if let traversalError {
            throw CodexActivityMonitor.MonitorError.unreadableFile(
                sessionsDirectory.path,
                traversalError.localizedDescription
            )
        }
        return files.sorted {
            if $0.modificationDate == $1.modificationDate { return $0.url.path < $1.url.path }
            return $0.modificationDate < $1.modificationDate
        }
    }

    private func bootstrap(_ file: SessionFile) throws -> (cursor: FileCursor, completions: [CodexTaskCompletion]) {
        let initialWindow: UInt64 = 1_048_576
        var window = min(file.size, initialWindow)

        while true {
            let startOffset = file.size - window
            let data = try read(file: file.url, from: startOffset)
            let prepared = prepareInitialData(data, startOffset: startOffset)
            var cursor = FileCursor(
                offset: file.size,
                pending: prepared.pending,
                parser: CodexActivityLogParser(fileIdentifier: file.url.deletingPathExtension().lastPathComponent)
            )
            var completions: [CodexTaskCompletion] = []
            for line in prepared.lines {
                if let completion = try cursor.parser.consume(
                    line.data,
                    file: file.url,
                    byteOffset: line.byteOffset,
                    completionCutoff: completionCutoff
                ) {
                    completions.append(completion)
                }
            }

            if cursor.parser.hasSeenTaskStart || startOffset == 0 {
                return (cursor, completions)
            }
            window = min(file.size, window * 2)
        }
    }

    private func prepareInitialData(
        _ data: Data,
        startOffset: UInt64
    ) -> (lines: [(data: Data, byteOffset: UInt64)], pending: Data) {
        var usable = data
        var usableStart = startOffset
        if startOffset > 0, let newline = usable.firstIndex(of: 0x0A) {
            let next = usable.index(after: newline)
            usableStart += UInt64(usable.distance(from: usable.startIndex, to: next))
            usable.removeSubrange(usable.startIndex..<next)
        }

        var lines: [(Data, UInt64)] = []
        var lineStart = usable.startIndex
        while let newline = usable[lineStart...].firstIndex(of: 0x0A) {
            let relativeOffset = usable.distance(from: usable.startIndex, to: lineStart)
            lines.append((Data(usable[lineStart..<newline]), usableStart + UInt64(relativeOffset)))
            lineStart = usable.index(after: newline)
        }
        return (lines, Data(usable[lineStart...]))
    }

    private func consumeCompleteLines(
        in cursor: inout FileCursor,
        file: URL
    ) throws -> [CodexTaskCompletion] {
        var completions: [CodexTaskCompletion] = []
        let bufferStart = cursor.offset - UInt64(cursor.pending.count)
        var lineStart = cursor.pending.startIndex

        while let newline = cursor.pending[lineStart...].firstIndex(of: 0x0A) {
            let relativeOffset = cursor.pending.distance(from: cursor.pending.startIndex, to: lineStart)
            if let completion = try cursor.parser.consume(
                Data(cursor.pending[lineStart..<newline]),
                file: file,
                byteOffset: bufferStart + UInt64(relativeOffset),
                completionCutoff: completionCutoff
            ) {
                completions.append(completion)
            }
            lineStart = cursor.pending.index(after: newline)
        }

        if lineStart != cursor.pending.startIndex {
            cursor.pending.removeSubrange(cursor.pending.startIndex..<lineStart)
        }
        return completions
    }

    private func fileSize(at url: URL) throws -> UInt64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let size = attributes[.size] as? NSNumber else {
                throw CodexActivityMonitor.MonitorError.unreadableFile(url.path, "file size is unavailable")
            }
            return size.uint64Value
        } catch let error as CodexActivityMonitor.MonitorError {
            throw error
        } catch {
            throw CodexActivityMonitor.MonitorError.unreadableFile(url.path, error.localizedDescription)
        }
    }

    private func read(file: URL, from offset: UInt64) throws -> Data {
        do {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            try handle.seek(toOffset: offset)
            return try handle.readToEnd() ?? Data()
        } catch {
            throw CodexActivityMonitor.MonitorError.unreadableFile(file.path, error.localizedDescription)
        }
    }
}
