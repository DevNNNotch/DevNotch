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

    func testGroupsProvidersByDescendingTotal() {
        let samples = [
            UsageSample(
                provider: .codex,
                inputTokens: 100,
                cachedInputTokens: 20,
                outputTokens: 10,
                timestamp: Date(timeIntervalSince1970: 1),
                sourceType: .localStructuredLog,
                sourceConfidence: .verified
            ),
            UsageSample(
                provider: .claudeCode,
                inputTokens: 200,
                cachedInputTokens: 50,
                outputTokens: 30,
                timestamp: Date(timeIntervalSince1970: 2),
                sourceType: .officialHook,
                sourceConfidence: .verified
            ),
            UsageSample(
                provider: .codex,
                inputTokens: 40,
                cachedInputTokens: 10,
                outputTokens: 5,
                timestamp: Date(timeIntervalSince1970: 3),
                sourceType: .localStructuredLog,
                sourceConfidence: .verified
            )
        ]

        let providers = UsageAggregator.providerTotals(samples)

        XCTAssertEqual(providers.map(\.provider), [.claudeCode, .codex])
        XCTAssertEqual(providers[0].total, 230)
        XCTAssertEqual(providers[1].input, 140)
        XCTAssertEqual(providers[1].cached, 30)
    }

    func testCalculatesCacheHitRateAndRejectsZeroInput() {
        let sample = UsageSample(
            provider: .openAI,
            inputTokens: 200,
            cachedInputTokens: 50,
            outputTokens: 20,
            timestamp: Date(timeIntervalSince1970: 1),
            sourceType: .officialAPI,
            sourceConfidence: .authoritative
        )
        let outputOnly = UsageSample(
            provider: .external,
            inputTokens: 0,
            outputTokens: 20,
            timestamp: Date(timeIntervalSince1970: 2),
            sourceType: .localEventAPI,
            sourceConfidence: .reported
        )

        XCTAssertEqual(UsageAggregator.cacheHitRate([sample]), 0.25)
        XCTAssertNil(UsageAggregator.cacheHitRate([outputOnly]))
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
