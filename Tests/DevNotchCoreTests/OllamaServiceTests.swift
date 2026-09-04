import XCTest
@testable import DevNotchCore

final class OllamaServiceTests: XCTestCase {
    func testDecodesStreamingChunk() throws {
        let chunk = try OllamaService.decodeChunk(
            #"{"message":{"role":"assistant","content":"hello"},"done":false,"error":null}"#
        )
        XCTAssertEqual(chunk.message?.content, "hello")
        XCTAssertFalse(chunk.done)
    }

    func testRejectsMalformedStreamingChunk() {
        XCTAssertThrowsError(try OllamaService.decodeChunk("not-json")) { error in
            XCTAssertTrue(error.localizedDescription.contains("could not be decoded"))
        }
    }
}
