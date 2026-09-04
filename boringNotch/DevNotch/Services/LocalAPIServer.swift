import Foundation
import Network

enum LocalAPIServerState: Equatable, Sendable {
    case starting
    case ready(port: UInt16)
    case waiting(reason: String)
    case failed(reason: String)
    case stopped
}

final class LocalAPIServer: @unchecked Sendable {
    private final class RateLimiter: @unchecked Sendable {
        private let lock = NSLock()
        private var requestTimes: [Date] = []
        private let limit: Int

        init(limit: Int) { self.limit = limit }

        func accept(now: Date = Date()) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            requestTimes.removeAll { now.timeIntervalSince($0) > 60 }
            guard requestTimes.count < limit else { return false }
            requestTimes.append(now)
            return true
        }
    }

    private let queue = DispatchQueue(label: "dev.devnotch.local-api", qos: .utility)
    private let router: LocalAPIRouter
    private let stateHandler: @Sendable (LocalAPIServerState) -> Void
    private let rateLimiter = RateLimiter(limit: 120)
    private var listener: NWListener?

    init(
        router: LocalAPIRouter,
        stateHandler: @escaping @Sendable (LocalAPIServerState) -> Void = { _ in }
    ) {
        self.router = router
        self.stateHandler = stateHandler
    }

    func start(port: UInt16 = 54731) throws {
        guard listener == nil else { return }
        guard let networkPort = NWEndpoint.Port(rawValue: port) else {
            throw LocalAPIError.validation("port \(port) is invalid")
        }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: networkPort)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.stateUpdateHandler = { [stateHandler] state in
            switch state {
            case .setup:
                stateHandler(.starting)
            case .waiting(let error):
                stateHandler(.waiting(reason: error.localizedDescription))
            case .ready:
                stateHandler(.ready(port: port))
            case .failed(let error):
                stateHandler(.failed(reason: error.localizedDescription))
            case .cancelled:
                stateHandler(.stopped)
            @unknown default:
                stateHandler(.failed(reason: "Network.framework returned an unknown listener state"))
            }
        }
        self.listener = listener
        stateHandler(.starting)
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var updatedBuffer = buffer
            if let data { updatedBuffer.append(data) }

            do {
                if updatedBuffer.count > LocalHTTPRequestParser.maximumBodySize + 16_384 {
                    throw LocalAPIError.requestTooLarge(LocalHTTPRequestParser.maximumBodySize)
                }
                if let expectedLength = try LocalHTTPRequestParser.expectedLength(in: updatedBuffer), updatedBuffer.count >= expectedLength {
                    let request = try LocalHTTPRequestParser.parse(updatedBuffer)
                    Task { await self.handle(request, connection: connection) }
                    return
                }
                if let error { throw LocalAPIError.malformedRequest(error.localizedDescription) }
                if isComplete { throw LocalAPIError.malformedRequest("connection closed before the request was complete") }
                self.receive(on: connection, buffer: updatedBuffer)
            } catch {
                self.sendError(error, on: connection)
            }
        }
    }

    private func handle(_ request: LocalAPIRequest, connection: NWConnection) async {
        guard rateLimiter.accept() else {
            sendError(LocalAPIError.rateLimited, on: connection)
            return
        }
        do {
            send(try await router.route(request), on: connection)
        } catch {
            sendError(error, on: connection)
        }
    }

    private func sendError(_ error: Error, on connection: NWConnection) {
        let apiError = error as? LocalAPIError ?? .validation(error.localizedDescription)
        do {
            send(try .json(status: apiError.statusCode, object: ["error": apiError.localizedDescription]), on: connection)
        } catch {
            stateHandler(.failed(reason: "Local API could not encode an error response: \(error.localizedDescription)"))
            connection.cancel()
        }
    }

    private func send(_ response: LocalAPIResponse, on connection: NWConnection) {
        let reason = Self.reasonPhrase(for: response.status)
        let header = "HTTP/1.1 \(response.status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(response.body.count)\r\nConnection: close\r\n\r\n"
        var data = Data(header.utf8)
        data.append(response.body)
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200: "OK"
        case 202: "Accepted"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 413: "Payload Too Large"
        case 429: "Too Many Requests"
        default: "Error"
        }
    }
}
