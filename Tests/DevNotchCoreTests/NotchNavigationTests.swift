import XCTest
@testable import DevNotchCore

final class NotchNavigationTests: XCTestCase {
    func testDefaultConfigurationStartsWithMusicAndShowsEveryPage() {
        XCTAssertEqual(
            NotchTabPreference.defaultConfiguration.map(\.view),
            [.home, .developer, .usage]
        )
        XCTAssertTrue(NotchTabPreference.defaultConfiguration.allSatisfy(\.isVisible))
    }

    func testNormalizationRemovesDuplicatesAndAppendsMissingPages() {
        let configuration = [
            NotchTabPreference(view: .usage, isVisible: false),
            NotchTabPreference(view: .usage, isVisible: true),
            NotchTabPreference(view: .home, isVisible: true)
        ]

        let result = NotchTabPreference.normalized(configuration)

        XCTAssertEqual(result.map(\.view), [.usage, .home, .developer])
        XCTAssertEqual(result.map(\.isVisible), [false, true, true])
    }

    func testCannotHideTheLastVisiblePage() throws {
        let configuration = [
            NotchTabPreference(view: .home, isVisible: false),
            NotchTabPreference(view: .developer, isVisible: true),
            NotchTabPreference(view: .usage, isVisible: false)
        ]

        XCTAssertThrowsError(
            try NotchTabPreference.settingVisibility(
                of: .developer,
                to: false,
                in: configuration
            )
        ) { error in
            XCTAssertEqual(error as? NotchNavigationError, .requiresVisibleView)
        }
    }

    func testMovingPagePreservesVisibility() throws {
        let configuration = [
            NotchTabPreference(view: .home, isVisible: true),
            NotchTabPreference(view: .developer, isVisible: false),
            NotchTabPreference(view: .usage, isVisible: true)
        ]

        let result = try NotchTabPreference.moving(.usage, to: 0, in: configuration)

        XCTAssertEqual(result.map(\.view), [.usage, .home, .developer])
        XCTAssertEqual(result.map(\.isVisible), [true, true, false])
    }
}
