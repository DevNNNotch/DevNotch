import Foundation
import XCTest
@testable import DevNotchCore

final class LocalAPITests: XCTestCase {
    func testParsesCompleteAuthenticatedRequest() throws {
        let body = Data(#"{"title":"Build","state":"running"}"#.utf8)
        var request = Data("POST /v1/events/build HTTP/1.1\r\nAuthorization: Bearer test\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
        request.append(body)

        let parsed = try LocalHTTPRequestParser.parse(request)
        XCTAssertEqual(parsed.method, "POST")
        XCTAssertEqual(parsed.path, "/v1/events/build")
        XCTAssertEqual(parsed.headers["authorization"], "Bearer test")
        XCTAssertEqual(parsed.body, body)
    }

    func testRejectsUnknownUsageFields() {
        let body = Data(#"{"provider":"external","inputTokens":1,"cachedInputTokens":0,"outputTokens":2,"timestamp":"2026-09-04T00:00:00Z","prompt":"must-not-be-accepted"}"#.utf8)
        XCTAssertThrowsError(
            try StrictJSONDecoder.decode(
                UsageEventPayload.self,
                from: body,
                allowedKeys: Set(UsageEventPayload.CodingKeys.allCases.map(\.rawValue))
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("unknown field"))
        }
    }

    func testRejectsInvalidProgress() {
        let payload = DeveloperEventPayload(
            id: nil,
            title: "Build",
            detail: nil,
            progress: 1.2,
            state: .running,
            timestamp: nil
        )
        XCTAssertThrowsError(try payload.validatedEvent(kind: .build))
    }

    func testRouterRejectsMissingJSONContentType() async {
        let router = LocalAPIRouter(
            accessToken: "test",
            usageStore: UsageStore(),
            eventStore: EventStore()
        )
        let request = LocalAPIRequest(
            method: "POST",
            path: "/v1/events/task",
            headers: ["authorization": "Bearer test"],
            body: Data(#"{"title":"Test","state":"running"}"#.utf8)
        )

        do {
            _ = try await router.route(request)
            XCTFail("Expected missing content type to be rejected")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Content-Type"))
        }
    }
}
