import Foundation

struct DeveloperEvent: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case log
        case task
        case build
    }

    enum State: String, Codable, Sendable {
        case queued
        case running
        case succeeded
        case failed
        case cancelled
    }

    let id: UUID
    let kind: Kind
    let title: String
    let detail: String?
    let progress: Double?
    let state: State
    let timestamp: Date

    init(
        id: UUID = UUID(),
        kind: Kind,
        title: String,
        detail: String? = nil,
        progress: Double? = nil,
        state: State,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.progress = progress
        self.state = state
        self.timestamp = timestamp
    }
}

actor EventStore {
    private var events: [DeveloperEvent] = []
    private var continuations: [UUID: AsyncStream<[DeveloperEvent]>.Continuation] = [:]

    func upsert(_ event: DeveloperEvent) {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events[index] = event
        } else {
            events.insert(event, at: 0)
        }
        events = Array(events.prefix(200))
        continuations.values.forEach { $0.yield(events) }
    }

    func updates() -> AsyncStream<[DeveloperEvent]> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.yield(events)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }
}
