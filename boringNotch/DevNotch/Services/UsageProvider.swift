import Foundation

struct ProviderStatus: Equatable, Sendable {
    enum State: String, Sendable {
        case ready
        case needsConfiguration
        case unavailable
        case failed
    }

    let state: State
    let reason: String
}

protocol UsageProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    func status() async -> ProviderStatus
    func fetchUsage(from startDate: Date, to endDate: Date) async throws -> [UsageSample]
}

enum UsageProviderError: LocalizedError, Equatable {
    case missingCredential(String)
    case invalidConfiguration(String)
    case unsupported(String)
    case httpStatus(Int, String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingCredential(let message),
             .invalidConfiguration(let message),
             .unsupported(let message),
             .invalidResponse(let message):
            return message
        case .httpStatus(let status, let body):
            return "Usage provider returned HTTP \(status): \(body)"
        }
    }
}

struct UnavailableUsageProvider: UsageProvider {
    let id: String
    let displayName: String
    let reason: String

    func status() async -> ProviderStatus {
        ProviderStatus(state: .unavailable, reason: reason)
    }

    func fetchUsage(from startDate: Date, to endDate: Date) async throws -> [UsageSample] {
        throw UsageProviderError.unsupported(reason)
    }

    static let trae = UnavailableUsageProvider(
        id: "trae",
        displayName: "Trae",
        reason: "No verified official token usage API or structured export is configured. Use the local usage event API instead."
    )

    static let codexSubscription = UnavailableUsageProvider(
        id: "codex-subscription",
        displayName: "Codex subscription",
        reason: "OpenAI organization API usage is not the same as Codex subscription quota. No verified subscription usage interface is configured."
    )
}
