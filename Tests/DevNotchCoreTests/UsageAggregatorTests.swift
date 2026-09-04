import Foundation
import XCTest
@testable import DevNotchCore

final class UsageAggregatorTests: XCTestCase {
    func testAggregatesIndependentTokenCategories() {
        let samples = [
            UsageSample(
                provider: .openAI,
                inputTokens: 100,
                cachedInputTokens: 40,
                outputTokens: 30,
                timestamp: Date(timeIntervalSince1970: 1),
                sourceType: .officialAPI,
                sourceConfidence: .authoritative
            ),
            UsageSample(
                provider: .claudeCode,
                inputTokens: 80,
                cachedInputTokens: 10,
                outputTokens: 20,
                totalTokens: 115,
                timestamp: Date(timeIntervalSince1970: 2),
                sourceType: .officialHook,
                sourceConfidence: .verified
            )
        ]

        let totals = UsageAggregator.totals(samples)
        XCTAssertEqual(totals.input, 180)
        XCTAssertEqual(totals.cached, 50)
        XCTAssertEqual(totals.output, 50)
        XCTAssertEqual(totals.total, 245)
    }

    func testUsageStoreReplacesSameSessionSnapshot() async {
        let store = UsageStore()
        let first = UsageSample(
            provider: .codex,
            sessionID: "session-1",
            inputTokens: 100,
            outputTokens: 10,
            timestamp: Date(timeIntervalSince1970: 1),
            sourceType: .localEventAPI,
            sourceConfidence: .reported
        )
        let latest = UsageSample(
            provider: .codex,
            sessionID: "session-1",
            inputTokens: 200,
            outputTokens: 20,
            timestamp: Date(timeIntervalSince1970: 2),
            sourceType: .localEventAPI,
            sourceConfidence: .reported
        )

        await store.append(first)
        await store.append(latest)
        var iterator = await store.updates().makeAsyncIterator()
        let values = await iterator.next()

        XCTAssertEqual(values, [latest])
    }
}
