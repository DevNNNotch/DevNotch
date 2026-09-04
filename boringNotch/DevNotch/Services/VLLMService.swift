import Foundation

struct VLLMModel: Decodable, Equatable, Sendable {
    let id: String
}

enum VLLMError: LocalizedError, Equatable {
    case invalidEndpoint(String)
    case invalidResponse(String)
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint(let message), .invalidResponse(let message): return message
        case .httpStatus(let status, let body): return "vLLM returned HTTP \(status): \(body)"
        }
    }
}

struct VLLMService: Sendable {
    private struct ModelsResponse: Decodable { let data: [VLLMModel] }

    private let baseURL: URL
    private let session: URLSession

    init(endpoint: String, session: URLSession = .shared) throws {
        guard let url = URL(string: endpoint), let scheme = url.scheme, ["http", "https"].contains(scheme) else {
            throw VLLMError.invalidEndpoint("vLLM endpoint must be a valid HTTP or HTTPS URL.")
        }
        self.baseURL = url
        self.session = session
    }

    func models() async throws -> [VLLMModel] {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/models"))
        request.timeoutInterval = 4
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VLLMError.invalidResponse("vLLM did not return an HTTP response.")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data.prefix(1_024), encoding: .utf8) ?? "Unreadable response body"
            throw VLLMError.httpStatus(httpResponse.statusCode, body)
        }
        do {
            return try JSONDecoder().decode(ModelsResponse.self, from: data).data
        } catch {
            throw VLLMError.invalidResponse("vLLM model list could not be decoded: \(error.localizedDescription)")
        }
    }
}
