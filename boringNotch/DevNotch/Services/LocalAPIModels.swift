import Foundation

struct LocalAPIRequest: Equatable, Sendable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
}

struct LocalAPIResponse: Sendable {
    let status: Int
    let body: Data

    static func json(status: Int, object: [String: String]) throws -> LocalAPIResponse {
        let data = try JSONEncoder().encode(object)
        return LocalAPIResponse(status: status, body: data)
    }
}

enum LocalAPIError: LocalizedError, Equatable {
    case malformedRequest(String)
    case requestTooLarge(Int)
    case unauthorized
    case rateLimited
    case unsupportedRoute(String)
    case validation(String)

    var errorDescription: String? {
        switch self {
        case .malformedRequest(let reason): return "Malformed HTTP request: \(reason)"
        case .requestTooLarge(let limit): return "Request body exceeds the \(limit)-byte limit."
        case .unauthorized: return "A valid Bearer token is required."
        case .rateLimited: return "Local API rate limit exceeded."
        case .unsupportedRoute(let route): return "Unsupported local API route: \(route)"
        case .validation(let reason): return "Request validation failed: \(reason)"
        }
    }

    var statusCode: Int {
        switch self {
        case .malformedRequest, .validation: 400
        case .unauthorized: 401
        case .unsupportedRoute: 404
        case .requestTooLarge: 413
        case .rateLimited: 429
        }
    }
}

enum LocalHTTPRequestParser {
    static let maximumBodySize = 1_048_576

    static func expectedLength(in data: Data) throws -> Int? {
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data[..<separator.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            throw LocalAPIError.malformedRequest("headers are not valid UTF-8")
        }
        let contentLength = headerText
            .components(separatedBy: "\r\n")
            .dropFirst()
            .compactMap { line -> Int? in
                let parts = line.split(separator: ":", maxSplits: 1)
                guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" else { return nil }
                return Int(parts[1].trimmingCharacters(in: .whitespaces))
            }
            .first ?? 0
        guard contentLength >= 0 else { throw LocalAPIError.malformedRequest("Content-Length is negative") }
        guard contentLength <= maximumBodySize else { throw LocalAPIError.requestTooLarge(maximumBodySize) }
        return separator.upperBound + contentLength
    }

    static func parse(_ data: Data) throws -> LocalAPIRequest {
        guard let expectedLength = try expectedLength(in: data), data.count >= expectedLength else {
            throw LocalAPIError.malformedRequest("request is incomplete")
        }
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)),
              let headerText = String(data: data[..<separator.lowerBound], encoding: .utf8)
        else {
            throw LocalAPIError.malformedRequest("header delimiter is missing")
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { throw LocalAPIError.malformedRequest("request line is missing") }
        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count == 3, requestParts[2].hasPrefix("HTTP/1.") else {
            throw LocalAPIError.malformedRequest("request line is invalid")
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { throw LocalAPIError.malformedRequest("header is invalid: \(line)") }
            headers[parts[0].trimmingCharacters(in: .whitespaces).lowercased()] = parts[1].trimmingCharacters(in: .whitespaces)
        }

        return LocalAPIRequest(
            method: String(requestParts[0]),
            path: String(requestParts[1]),
            headers: headers,
            body: data[separator.upperBound..<expectedLength]
        )
    }
}

struct UsageEventPayload: Decodable, Sendable {
    let provider: UsageSample.Provider
    let accountOrWorkspace: String?
    let model: String?
    let sessionID: String?
    let inputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int
    let totalTokens: Int?
    let timestamp: Date

    enum CodingKeys: String, CodingKey, CaseIterable {
        case provider, accountOrWorkspace, model, sessionID, inputTokens, cachedInputTokens, outputTokens, totalTokens, timestamp
    }

    func validatedSample() throws -> UsageSample {
        guard inputTokens >= 0, cachedInputTokens >= 0, outputTokens >= 0 else {
            throw LocalAPIError.validation("token counts must be non-negative integers")
        }
        if let totalTokens, totalTokens < inputTokens + outputTokens {
            throw LocalAPIError.validation("totalTokens cannot be smaller than inputTokens + outputTokens")
        }
        return UsageSample(
            provider: provider,
            accountOrWorkspace: accountOrWorkspace,
            model: model,
            sessionID: sessionID,
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens,
            timestamp: timestamp,
            sourceType: .localEventAPI,
            sourceConfidence: .reported
        )
    }
}

struct DeveloperEventPayload: Decodable, Sendable {
    let id: UUID?
    let title: String
    let detail: String?
    let progress: Double?
    let state: DeveloperEvent.State
    let timestamp: Date?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, title, detail, progress, state, timestamp
    }

    func validatedEvent(kind: DeveloperEvent.Kind) throws -> DeveloperEvent {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, cleanTitle.count <= 200 else {
            throw LocalAPIError.validation("title must contain 1 to 200 characters")
        }
        if let progress, !(0...1).contains(progress) {
            throw LocalAPIError.validation("progress must be between 0 and 1")
        }
        if let detail, detail.count > 8_000 {
            throw LocalAPIError.validation("detail cannot exceed 8,000 characters")
        }
        return DeveloperEvent(
            id: id ?? UUID(),
            kind: kind,
            title: cleanTitle,
            detail: detail,
            progress: progress,
            state: state,
            timestamp: timestamp ?? Date()
        )
    }
}

enum StrictJSONDecoder {
    static func decode<T: Decodable>(_ type: T.Type, from data: Data, allowedKeys: Set<String>) throws -> T {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LocalAPIError.validation("body must be a JSON object")
        }
        let unknownKeys = Set(object.keys).subtracting(allowedKeys)
        guard unknownKeys.isEmpty else {
            throw LocalAPIError.validation("unknown field(s): \(unknownKeys.sorted().joined(separator: ", "))")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw LocalAPIError.validation(error.localizedDescription)
        }
    }
}
