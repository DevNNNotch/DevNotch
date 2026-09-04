import XCTest
@testable import DevNotchCore

final class ClipboardClassifierTests: XCTestCase {
    func testClassifiesGitDiffBeforeSourceCode() {
        let content = """
        diff --git a/App.swift b/App.swift
        --- a/App.swift
        +++ b/App.swift
        @@ -1 +1 @@
        -let state = false
        +let state = true
        """
        XCTAssertEqual(ClipboardClassifier.classify(content)?.kind, .gitDiff)
    }

    func testClassifiesErrorLog() {
        XCTAssertEqual(
            ClipboardClassifier.classify("Fatal: build failed\nError: missing module DevNotchCore")?.kind,
            .errorLog
        )
    }

    func testBlocksCredentials() {
        let result = ClipboardClassifier.classify("-----BEGIN PRIVATE KEY-----\nnot-a-real-test-key")
        XCTAssertEqual(result?.kind, .sensitive)
        XCTAssertEqual(result?.suggestedAction, "AI actions are blocked")
    }
}
