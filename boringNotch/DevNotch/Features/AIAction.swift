import Foundation

enum AIAction: String, CaseIterable, Identifiable, Sendable {
    case explainCode = "Explain Code"
    case diagnoseError = "Diagnose Error"
    case suggestFix = "Suggest Fix"
    case polish = "Polish"
    case translate = "Translate"
    case generateCommitMessage = "Generate Commit Message"

    var id: String { rawValue }

    static func available(for kind: ClipboardContentKind) -> [AIAction] {
        switch kind {
        case .sourceCode: [.explainCode, .suggestFix]
        case .errorLog: [.diagnoseError, .suggestFix]
        case .gitDiff: [.generateCommitMessage, .explainCode]
        case .englishText: [.polish, .translate]
        case .generalText: [.polish, .translate]
        case .sensitive: []
        }
    }

    func prompt(for content: String) -> String {
        let instruction: String
        switch self {
        case .explainCode:
            instruction = "Explain this code concisely. Describe its behavior, important assumptions, and concrete risks."
        case .diagnoseError:
            instruction = "Diagnose this error from the evidence shown. Identify the most likely root cause and provide verifiable debugging steps."
        case .suggestFix:
            instruction = "Propose the smallest correct fix. Explain why it fixes the root cause and include only necessary code changes."
        case .polish:
            instruction = "Polish this text while preserving its meaning and technical details. Return only the improved text."
        case .translate:
            instruction = "Translate this text between English and Simplified Chinese based on its current language. Preserve code and identifiers exactly."
        case .generateCommitMessage:
            instruction = "Generate one Conventional Commit message for this diff. Return a subject under 72 characters and an optional concise body."
        }
        return "\(instruction)\n\n--- INPUT ---\n\(content)"
    }
}
