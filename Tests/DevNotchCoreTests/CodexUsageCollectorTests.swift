import XCTest
@testable import DevNotchCore

final class CodexUsageCollectorTests: XCTestCase {
    func testParsesLatestCodexTokenSnapshot() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = directory.appendingPathComponent("session.jsonl")
        let fixture = """
        {"timestamp":"2026-09-05T01:00:00Z","type":"session_meta","payload":{"id":"session-1","cwd":"/tmp/project"}}
        {"timestamp":"2026-09-05T01:00:01Z","type":"turn_context","payload":{"model":"gpt-5"}}
        {"timestamp":"2026-09-05T01:00:02Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":30,"total_tokens":130}}}}
        {"timestamp":"2026-09-05T01:00:03Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":240,"cached_input_tokens":80,"output_tokens":60,"total_tokens":300}}}}
        """
        try fixture.write(to: session, atomically: true, encoding: .utf8)

        let sample = try XCTUnwrap(
            CodexUsageCollector(sessionsDirectory: directory).parseSession(at: session)
        )

        XCTAssertEqual(sample.provider, .codex)
        XCTAssertEqual(sample.sessionID, "session-1")
        XCTAssertEqual(sample.accountOrWorkspace, "/tmp/project")
        XCTAssertEqual(sample.model, "gpt-5")
        XCTAssertEqual(sample.inputTokens, 240)
        XCTAssertEqual(sample.cachedInputTokens, 80)
        XCTAssertEqual(sample.outputTokens, 60)
        XCTAssertEqual(sample.totalTokens, 300)
        XCTAssertEqual(sample.sourceType, .localStructuredLog)
        XCTAssertEqual(sample.sourceConfidence, .verified)
    }

    func testReportsMalformedCodexRecordWithLineNumber() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = directory.appendingPathComponent("broken.jsonl")
        try "{\"type\":\"session_meta\",\"payload\":{}}\nnot-json"
            .write(to: session, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try CodexUsageCollector(sessionsDirectory: directory).parseSession(at: session)
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("broken.jsonl:2"))
        }
    }

    func testParsesRecordAcrossReadChunks() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = directory.appendingPathComponent("large-session.jsonl")
        let padding = String(repeating: "x", count: 300_000)
        let fixture = """
        {"type":"event_msg","payload":{"type":"message","text":"\(padding)"}}
        {"timestamp":"2026-09-05T01:00:02Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10,"cached_input_tokens":2,"output_tokens":3,"total_tokens":13}}}}
        """
        try fixture.write(to: session, atomically: true, encoding: .utf8)

        let sample = try XCTUnwrap(
            CodexUsageCollector(sessionsDirectory: directory).parseSession(at: session)
        )

        XCTAssertEqual(sample.inputTokens, 10)
        XCTAssertEqual(sample.outputTokens, 3)
        XCTAssertEqual(sample.totalTokens, 13)
    }

    func testRejectsMissingSessionsDirectory() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        XCTAssertThrowsError(
            try CodexUsageCollector(sessionsDirectory: missing).collect(since: .distantPast)
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("does not exist"))
        }
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
