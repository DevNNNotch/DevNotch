import Foundation

enum ClipboardContentKind: String, Codable, Equatable, Sendable {
    case sourceCode
    case errorLog
    case gitDiff
    case englishText
    case generalText
    case sensitive
}

struct ClipboardContext: Equatable, Sendable {
    let kind: ClipboardContentKind
    let title: String
    let suggestedAction: String
    let content: String
}

enum ClipboardClassifier {
    private static let secretPatterns = [
        #"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"#,
        #"\bsk-[A-Za-z0-9_-]{20,}\b"#,
        #"\bgh[pousr]_[A-Za-z0-9]{20,}\b"#,
        #"\beyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"#
    ]

    static func classify(_ rawContent: String) -> ClipboardContext? {
        let content = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard content.count >= 8 else { return nil }

        if secretPatterns.contains(where: { content.range(of: $0, options: .regularExpression) != nil }) {
            return ClipboardContext(kind: .sensitive, title: "Sensitive content detected", suggestedAction: "AI actions are blocked", content: content)
        }

        if content.hasPrefix("diff --git") || (content.contains("@@") && content.contains("+++ ") && content.contains("--- ")) {
            return ClipboardContext(kind: .gitDiff, title: "Git diff copied", suggestedAction: "Generate Commit Message", content: content)
        }

        let lowercase = content.lowercased()
        let errorSignals = ["error:", "exception", "traceback", "fatal:", "stack trace", "segmentation fault"]
        if errorSignals.contains(where: lowercase.contains) {
            return ClipboardContext(kind: .errorLog, title: "Error log copied", suggestedAction: "Diagnose Error", content: content)
        }

        let codeSignals = ["func ", "class ", "struct ", "import ", "const ", "let ", "var ", "=>", "</", "#!/"]
        if content.contains("\n") && codeSignals.filter(content.contains).count >= 2 {
            return ClipboardContext(kind: .sourceCode, title: "Code copied", suggestedAction: "Explain Code", content: content)
        }

        let letters = content.unicodeScalars.filter(CharacterSet.letters.contains)
        let asciiLetters = letters.filter { $0.isASCII }
        if letters.count > 20, Double(asciiLetters.count) / Double(letters.count) > 0.85 {
            return ClipboardContext(kind: .englishText, title: "English text copied", suggestedAction: "Polish or Translate", content: content)
        }

        return ClipboardContext(kind: .generalText, title: "Text copied", suggestedAction: "Polish", content: content)
    }
}
