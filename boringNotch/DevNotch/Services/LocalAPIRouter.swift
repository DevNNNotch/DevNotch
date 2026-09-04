import Foundation

struct LocalAPIRouter: Sendable {
    let accessToken: String
    let usageStore: UsageStore
    let eventStore: EventStore

    func route(_ request: LocalAPIRequest) async throws -> LocalAPIResponse {
        guard request.headers["authorization"] == "Bearer \(accessToken)" else {
            throw LocalAPIError.unauthorized
        }

        if request.method == "GET", request.path == "/v1/health" {
            return try .json(status: 200, object: ["status": "ok", "service": "DevNotch Local API"])
        }

        guard request.method == "POST" else {
            throw LocalAPIError.unsupportedRoute("\(request.method) \(request.path)")
        }
        let contentType = request.headers["content-type"]?.split(separator: ";", maxSplits: 1).first?.lowercased()
        guard contentType == "application/json" else {
            throw LocalAPIError.validation("Content-Type must be application/json")
        }

        switch request.path {
        case "/v1/usage/events":
            let keys = Set(UsageEventPayload.CodingKeys.allCases.map(\.rawValue))
            let payload = try StrictJSONDecoder.decode(UsageEventPayload.self, from: request.body, allowedKeys: keys)
            await usageStore.append(try payload.validatedSample())
            return try .json(status: 202, object: ["status": "accepted"])
        case "/v1/events/log", "/v1/events/task", "/v1/events/build":
            let keys = Set(DeveloperEventPayload.CodingKeys.allCases.map(\.rawValue))
            let payload = try StrictJSONDecoder.decode(DeveloperEventPayload.self, from: request.body, allowedKeys: keys)
            let kind: DeveloperEvent.Kind = request.path.hasSuffix("/log") ? .log : request.path.hasSuffix("/build") ? .build : .task
            await eventStore.upsert(try payload.validatedEvent(kind: kind))
            return try .json(status: 202, object: ["status": "accepted"])
        default:
            throw LocalAPIError.unsupportedRoute("\(request.method) \(request.path)")
        }
    }
}
