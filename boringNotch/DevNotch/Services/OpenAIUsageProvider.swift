import Foundation

struct OpenAIUsageProvider: UsageProvider {
    private struct ResponsePage: Decodable {
        let data: [Bucket]
        let hasMore: Bool
        let nextPage: String?

        enum CodingKeys: String, CodingKey {
            case data
            case hasMore = "has_more"
            case nextPage = "next_page"
        }
    }

    private struct Bucket: Decodable {
        let startTime: Int
        let results: [Result]

        enum CodingKeys: String, CodingKey {
            case startTime = "start_time"
            case results
        }
    }

    private struct Result: Decodable {
        let inputTokens: Int
        let inputCachedTokens: Int
        let outputTokens: Int
        let projectID: String?
        let userID: String?
        let model: String?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case inputCachedTokens = "input_cached_tokens"
            case outputTokens = "output_tokens"
            case projectID = "project_id"
            case userID = "user_id"
            case model
        }
    }

    let id = "openai-api"
    let displayName = "OpenAI API"

    private let keychain: KeychainStore
    private let session: URLSession
    private let endpoint: URL

    init(
        keychain: KeychainStore = KeychainStore(),
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://api.openai.com/v1/organization/usage/completions")!
    ) {
        self.keychain = keychain
        self.session = session
        self.endpoint = endpoint
    }

    func status() async -> ProviderStatus {
        do {
            return try keychain.string(for: "openai-admin-key")?.isEmpty == false
                ? ProviderStatus(state: .ready, reason: "OpenAI organization usage is configured.")
                : ProviderStatus(state: .needsConfiguration, reason: "An OpenAI organization Admin Key is required.")
        } catch {
            return ProviderStatus(state: .failed, reason: error.localizedDescription)
        }
    }

    func fetchUsage(from startDate: Date, to endDate: Date) async throws -> [UsageSample] {
        guard startDate < endDate else {
            throw UsageProviderError.invalidConfiguration("Usage start date must be earlier than the end date.")
        }
        guard let adminKey = try keychain.string(for: "openai-admin-key"), !adminKey.isEmpty else {
            throw UsageProviderError.missingCredential("OpenAI organization usage requires an Admin Key stored in Keychain.")
        }

        var allSamples: [UsageSample] = []
        var nextPage: String?
        repeat {
            let page = try await fetchPage(adminKey: adminKey, startDate: startDate, endDate: endDate, page: nextPage)
            allSamples.append(contentsOf: page.data.flatMap(Self.samples(from:)))
            nextPage = page.hasMore ? page.nextPage : nil
            if page.hasMore && nextPage == nil {
                throw UsageProviderError.invalidResponse("OpenAI Usage API reported more data but omitted next_page.")
            }
        } while nextPage != nil
        return allSamples
    }

    private func fetchPage(adminKey: String, startDate: Date, endDate: Date, page: String?) async throws -> ResponsePage {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw UsageProviderError.invalidConfiguration("OpenAI Usage API endpoint is invalid: \(endpoint.absoluteString)")
        }
        var queryItems = [
            URLQueryItem(name: "start_time", value: String(Int(startDate.timeIntervalSince1970))),
            URLQueryItem(name: "end_time", value: String(Int(endDate.timeIntervalSince1970))),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "group_by[]", value: "project_id"),
            URLQueryItem(name: "group_by[]", value: "user_id"),
            URLQueryItem(name: "group_by[]", value: "model"),
            URLQueryItem(name: "limit", value: "31")
        ]
        if let page { queryItems.append(URLQueryItem(name: "page", value: page)) }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw UsageProviderError.invalidConfiguration("OpenAI Usage API query could not be constructed.")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(adminKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UsageProviderError.invalidResponse("OpenAI Usage API did not return an HTTP response.")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data.prefix(1_024), encoding: .utf8) ?? "Unreadable response body"
            throw UsageProviderError.httpStatus(httpResponse.statusCode, body)
        }

        do {
            return try JSONDecoder().decode(ResponsePage.self, from: data)
        } catch {
            throw UsageProviderError.invalidResponse("OpenAI Usage API response could not be decoded: \(error.localizedDescription)")
        }
    }

    private static func samples(from bucket: Bucket) -> [UsageSample] {
        bucket.results.map { result in
            UsageSample(
                provider: .openAI,
                accountOrWorkspace: result.projectID ?? result.userID,
                model: result.model,
                inputTokens: result.inputTokens,
                cachedInputTokens: result.inputCachedTokens,
                outputTokens: result.outputTokens,
                timestamp: Date(timeIntervalSince1970: TimeInterval(bucket.startTime)),
                sourceType: .officialAPI,
                sourceConfidence: .authoritative
            )
        }
    }
}
