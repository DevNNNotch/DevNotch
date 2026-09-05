import Foundation

struct CodexTaskActivity: Equatable, Identifiable, Sendable {
    let turnID: String
    let sessionID: String
    let title: String
    let startedAt: Date

    var id: String { turnID }
}

struct CodexTaskCompletion: Equatable, Identifiable, Sendable {
    let turnID: String
    let sessionID: String
    let title: String
    let preview: String
    let completedAt: Date

    var id: String { turnID }
}

enum CodexActivityUpdate: Equatable, Sendable {
    case runningTasks([CodexTaskActivity])
    case completed(CodexTaskCompletion)
}
