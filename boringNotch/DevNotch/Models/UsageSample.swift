import Foundation

struct UsageSample: Codable, Equatable, Identifiable, Sendable {
    enum Provider: String, Codable, CaseIterable, Sendable {
        case openAI = "openai"
        case codex = "codex"
        case claudeCode = "claude-code"
        case trae
        case external
    }

    enum SourceType: String, Codable, Sendable {
        case officialAPI = "official-api"
        case officialHook = "official-hook"
        case localStructuredLog = "local-structured-log"
        case localEventAPI = "local-event-api"
    }

    enum Confidence: String, Codable, Sendable {
        case authoritative
        case verified
        case reported
    }

    let id: UUID
    let provider: Provider
    let accountOrWorkspace: String?
    let model: String?
    let sessionID: String?
    let inputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int
    let totalTokens: Int
    let estimatedCost: Decimal?
    let currency: String?
    let timestamp: Date
    let sourceType: SourceType
    let sourceConfidence: Confidence
    let collectionError: String?

    init(
        id: UUID = UUID(),
        provider: Provider,
        accountOrWorkspace: String? = nil,
        model: String? = nil,
        sessionID: String? = nil,
        inputTokens: Int,
        cachedInputTokens: Int = 0,
        outputTokens: Int,
        totalTokens: Int? = nil,
        estimatedCost: Decimal? = nil,
        currency: String? = nil,
        timestamp: Date,
        sourceType: SourceType,
        sourceConfidence: Confidence,
        collectionError: String? = nil
    ) {
        self.id = id
        self.provider = provider
        self.accountOrWorkspace = accountOrWorkspace
        self.model = model
        self.sessionID = sessionID
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens ?? inputTokens + outputTokens
        self.estimatedCost = estimatedCost
        self.currency = currency
        self.timestamp = timestamp
        self.sourceType = sourceType
        self.sourceConfidence = sourceConfidence
        self.collectionError = collectionError
    }
}

enum UsageAggregator {
    static func totals(_ samples: [UsageSample]) -> (input: Int, cached: Int, output: Int, total: Int) {
        samples.reduce(into: (0, 0, 0, 0)) { result, sample in
            result.0 += sample.inputTokens
            result.1 += sample.cachedInputTokens
            result.2 += sample.outputTokens
            result.3 += sample.totalTokens
        }
    }
}

actor UsageStore {
    private var samples: [UsageSample] = []
    private var continuations: [UUID: AsyncStream<[UsageSample]>.Continuation] = [:]

    func append(_ sample: UsageSample) {
        if let sessionID = sample.sessionID,
           let index = samples.firstIndex(where: {
               $0.provider == sample.provider && $0.sessionID == sessionID && $0.sourceType == sample.sourceType
           }) {
            samples[index] = sample
        } else {
            samples.append(sample)
        }
        samples.sort { $0.timestamp > $1.timestamp }
        if samples.count > 2_000 {
            samples.removeLast(samples.count - 2_000)
        }
        publish()
    }

    func replace(_ replacement: [UsageSample], for provider: UsageSample.Provider) {
        samples.removeAll { $0.provider == provider && $0.sourceType != .localEventAPI }
        samples.append(contentsOf: replacement)
        samples.sort { $0.timestamp > $1.timestamp }
        if samples.count > 2_000 {
            samples.removeLast(samples.count - 2_000)
        }
        publish()
    }

    func updates() -> AsyncStream<[UsageSample]> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.yield(samples)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    private func publish() {
        continuations.values.forEach { $0.yield(samples) }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }
}
