import Foundation

struct OllamaModel: Decodable, Equatable, Sendable {
    let name: String
    let size: Int64?
    let modifiedAt: String?

    enum CodingKeys: String, CodingKey {
        case name
        case size
        case modifiedAt = "modified_at"
    }
}

struct OllamaChatChunk: Decodable, Equatable, Sendable {
    struct Message: Decodable, Equatable, Sendable {
        let role: String
        let content: String
    }

    let message: Message?
    let done: Bool
    let error: String?
}

enum OllamaError: LocalizedError, Equatable {
    case invalidEndpoint(String)
    case httpStatus(Int, String)
    case invalidResponse(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint(let message), .invalidResponse(let message), .server(let message):
            return message
        case .httpStatus(let status, let body):
            return "Ollama returned HTTP \(status): \(body)"
        }
    }
}

struct OllamaService: Sendable {
    private struct ModelsResponse: Decodable { let models: [OllamaModel] }

    let baseURL: URL
    let session: URLSession

    init(endpoint: String, session: URLSession = .shared) throws {
        guard let url = URL(string: endpoint), let scheme = url.scheme, ["http", "https"].contains(scheme) else {
            throw OllamaError.invalidEndpoint("Ollama endpoint must be a valid HTTP or HTTPS URL.")
        }
        self.baseURL = url
        self.session = session
    }

    func models() async throws -> [OllamaModel] {
        let request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        do {
            return try JSONDecoder().decode(ModelsResponse.self, from: data).models
        } catch {
            throw OllamaError.invalidResponse("Ollama model list could not be decoded: \(error.localizedDescription)")
        }
    }

    func streamChat(model: String, prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let url = baseURL.appendingPathComponent("api/chat")
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: [
                        "model": model,
                        "stream": true,
                        "messages": [["role": "user", "content": prompt]]
                    ])

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw OllamaError.invalidResponse("Ollama did not return an HTTP response.")
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        throw OllamaError.httpStatus(httpResponse.statusCode, "Streaming request rejected")
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard !line.isEmpty else { continue }
                        let chunk = try Self.decodeChunk(line)
                        if let error = chunk.error { throw OllamaError.server(error) }
                        if let content = chunk.message?.content, !content.isEmpty { continuation.yield(content) }
                        if chunk.done { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func decodeChunk(_ line: String) throws -> OllamaChatChunk {
        guard let data = line.data(using: .utf8) else {
            throw OllamaError.invalidResponse("Ollama stream contained invalid UTF-8.")
        }
        do {
            return try JSONDecoder().decode(OllamaChatChunk.self, from: data)
        } catch {
            throw OllamaError.invalidResponse("Ollama stream chunk could not be decoded: \(error.localizedDescription)")
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse("Ollama did not return an HTTP response.")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data.prefix(1_024), encoding: .utf8) ?? "Unreadable response body"
            throw OllamaError.httpStatus(httpResponse.statusCode, body)
        }
    }
}
