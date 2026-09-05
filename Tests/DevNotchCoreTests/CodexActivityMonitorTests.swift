import XCTest
@testable import DevNotchCore

final class CodexActivityMonitorTests: XCTestCase {
    private let file = URL(fileURLWithPath: "/tmp/codex-session.jsonl")
    private let cutoff = ISO8601DateFormatter().date(from: "2026-09-05T00:00:00Z")!

    func testParsesRunningTaskTitleFromInjectedRequestContext() throws {
        var parser = CodexActivityLogParser(fileIdentifier: "session-file")

        try consume(
            #"{"timestamp":"2026-09-05T01:00:00Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}"#,
            with: &parser
        )
        try consume(
            #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<in-app-browser-context>ignore this</in-app-browser-context>\n\n## My request:\n修复构建错误并运行测试"}]}}"#,
            with: &parser
        )

        XCTAssertEqual(parser.activeTask?.turnID, "turn-1")
        XCTAssertEqual(parser.activeTask?.title, "修复构建错误并运行测试")
    }

    func testParsesCodexUnixLifecycleTimestamps() throws {
        var parser = CodexActivityLogParser(fileIdentifier: "session-file")
        try consume(
            #"{"timestamp":"2026-09-05T01:00:00Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1","started_at":1788566400}}"#,
            with: &parser
        )
        try consume(
            #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Verify timestamps"}]}}"#,
            with: &parser
        )
        let completion = try consume(
            #"{"timestamp":"2026-09-05T01:01:00Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1","completed_at":1788566460,"last_agent_message":"Verified."}}"#,
            with: &parser
        )

        XCTAssertEqual(parser.hasSeenTaskStart, true)
        XCTAssertEqual(completion?.completedAt.timeIntervalSince1970, 1_788_566_460)
    }

    func testCreatesCompletionWithFinalResponsePreview() throws {
        var parser = CodexActivityLogParser(fileIdentifier: "session-file")
        try consume(
            #"{"timestamp":"2026-09-05T01:00:00Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}"#,
            with: &parser
        )
        try consume(
            #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Run the release build"}]}}"#,
            with: &parser
        )
        let completion = try consume(
            #"{"timestamp":"2026-09-05T01:01:00Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1","last_agent_message":"Build passed.\nAll tests succeeded."}}"#,
            with: &parser
        )

        XCTAssertEqual(completion?.title, "Run the release build")
        XCTAssertEqual(completion?.preview, "Build passed.\nAll tests succeeded.")
        XCTAssertNil(parser.activeTask)
    }

    func testAbortedTurnStopsRunningWithoutCompletion() throws {
        var parser = CodexActivityLogParser(fileIdentifier: "session-file")
        try consume(
            #"{"timestamp":"2026-09-05T01:00:00Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}"#,
            with: &parser
        )
        let completion = try consume(
            #"{"timestamp":"2026-09-05T01:00:05Z","type":"event_msg","payload":{"type":"turn_aborted","turn_id":"turn-1"}}"#,
            with: &parser
        )

        XCTAssertNil(completion)
        XCTAssertNil(parser.activeTask)
    }

    func testCompletionWithoutFinalMessageReportsSchemaError() throws {
        var parser = CodexActivityLogParser(fileIdentifier: "session-file")
        try consume(
            #"{"timestamp":"2026-09-05T01:00:00Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}"#,
            with: &parser
        )
        try consume(
            #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Run tests"}]}}"#,
            with: &parser
        )

        XCTAssertThrowsError(
            try consume(
                #"{"timestamp":"2026-09-05T01:01:00Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1"}}"#,
                with: &parser
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("last_agent_message"))
        }
    }

    func testScannerReadsAppendedCompletionWithoutReprocessingHistory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = directory.appendingPathComponent("session.jsonl")
        let startedAt = ISO8601DateFormatter().string(from: Date())
        let initial = """
        {"timestamp":"\(startedAt)","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-live"}}
        {"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Validate incremental monitoring"}]}}
        """ + "\n"
        try initial.write(to: session, atomically: true, encoding: .utf8)

        var scanner = CodexActivityScanner(
            sessionsDirectory: directory,
            discoveryInterval: 60,
            completionCutoff: Date().addingTimeInterval(-1)
        )
        let initialUpdates = try scanner.scan(forceDiscovery: true)
        XCTAssertEqual(
            initialUpdates,
            [.runningTasks([
                CodexTaskActivity(
                    turnID: "turn-live",
                    sessionID: "session",
                    title: "Validate incremental monitoring",
                    startedAt: try XCTUnwrap(ISO8601DateFormatter().date(from: startedAt))
                ),
            ])]
        )

        let completedAt = ISO8601DateFormatter().string(from: Date())
        let completion = """
        {"timestamp":"\(completedAt)","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-live","last_agent_message":"Incremental monitoring passed."}}
        """ + "\n"
        let handle = try FileHandle(forWritingTo: session)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(completion.utf8))
        try handle.close()

        let updates = try scanner.scan()
        guard updates.count == 2 else {
            return XCTFail("Expected completion and empty running-task updates, received \(updates.count).")
        }
        guard case .completed(let result) = updates[0] else {
            return XCTFail("Expected a completion update before the running-task snapshot.")
        }
        XCTAssertEqual(result.title, "Validate incremental monitoring")
        XCTAssertEqual(result.preview, "Incremental monitoring passed.")
        XCTAssertEqual(updates[1], .runningTasks([]))
    }

    @discardableResult
    private func consume(
        _ line: String,
        with parser: inout CodexActivityLogParser
    ) throws -> CodexTaskCompletion? {
        try parser.consume(
            Data(line.utf8),
            file: file,
            byteOffset: 0,
            completionCutoff: cutoff
        )
    }
}
