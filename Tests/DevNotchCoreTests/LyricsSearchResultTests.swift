import XCTest
@testable import DevNotchCore

final class LyricsSearchResultTests: XCTestCase {
    func testDecodesInstrumentalTrackWithoutLyrics() throws {
        let data = Data(
            #"{"instrumental":true,"plainLyrics":null,"syncedLyrics":null}"#.utf8
        )

        let result = try JSONDecoder().decode(LRCLIBSearchResult.self, from: data)

        XCTAssertTrue(result.instrumental)
        XCTAssertNil(result.plainLyrics)
        XCTAssertNil(result.syncedLyrics)
    }

    func testRequiresExplicitInstrumentalFlag() {
        let data = Data(
            #"{"plainLyrics":null,"syncedLyrics":null}"#.utf8
        )

        XCTAssertThrowsError(try JSONDecoder().decode(LRCLIBSearchResult.self, from: data))
    }
}
