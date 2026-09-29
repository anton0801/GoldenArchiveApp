import Foundation
import Network

enum ArchiveHeaderlessHTTP {
    struct Response {
        let statusCode: Int
        let headers: [String: String]
        let body: Data
    }

    enum Failure: Error {
        case invalidURL
        case invalidResponse
        case responseTooLarge
        case timedOut
    }

    static func post(to url: URL, body: Data, timeout: TimeInterval) async throws -> Response {
        var destination = url
        for _ in 0..<4 {
            let response = try await exchange(with: destination, body: body, timeout: timeout)
            if (300...399).contains(response.statusCode),
               let location = response.headers["location"],
               let redirected = URL(string: location, relativeTo: destination)?.absoluteURL,
               redirected.scheme?.lowercased() == "https" {
                destination = redirected
                continue
            }
            return response
        }
        throw Failure.invalidResponse
    }

    private static func exchange(with url: URL, body: Data, timeout: TimeInterval) async throws -> Response {
        guard url.scheme?.lowercased() == "https",
              let host = url.host,
              let portNumber = UInt16(exactly: url.port ?? 443),
              let port = NWEndpoint.Port(rawValue: portNumber),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw Failure.invalidURL
        }

        var target = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        if let query = components.percentEncodedQuery { target += "?\(query)" }
        let hostHeader = url.port.map { "\(host):\($0)" } ?? host
        let headers = "POST \(target) HTTP/1.1\r\nHost: \(hostHeader)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nAccept-Encoding: identity\r\nConnection: close\r\n\r\n"
        var request = Data(headers.utf8)
        request.append(body)

        return try await withCheckedThrowingContinuation { continuation in
            let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tls)
            let exchange = Exchange(connection: connection, request: request, timeout: timeout, continuation: continuation)
            exchange.start()
        }
    }

    private final class Exchange {
        private let connection: NWConnection
        private let request: Data
        private let timeout: TimeInterval
        private let continuation: CheckedContinuation<Response, Error>
        private let queue = DispatchQueue(label: "GoldenArchive.HeaderlessHTTP")
        private var received = Data()
        private var finished = false

        init(connection: NWConnection, request: Data, timeout: TimeInterval,
             continuation: CheckedContinuation<Response, Error>) {
            self.connection = connection
            self.request = request
            self.timeout = timeout
            self.continuation = continuation
        }

        func start() {
            connection.stateUpdateHandler = { [self] state in
                switch state {
                case .ready:
                    connection.send(content: request, completion: .contentProcessed { [self] error in
                        if let error {
                            finish(.failure(error))
                        } else {
                            receive()
                        }
                    })
                case .failed(let error):
                    finish(.failure(error))
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { [self] in
                finish(.failure(Failure.timedOut))
            }
        }

        private func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [self] data, _, complete, error in
                if let data { received.append(data) }
                if received.count > 2_000_000 {
                    finish(.failure(Failure.responseTooLarge))
                } else if let error {
                    finish(.failure(error))
                } else {
                    do {
                        if let response = try parse(received, complete: complete) {
                            finish(.success(response))
                        } else if complete {
                            finish(.failure(Failure.invalidResponse))
                        } else {
                            receive()
                        }
                    } catch {
                        finish(.failure(error))
                    }
                }
            }
        }

        private func finish(_ result: Result<Response, Error>) {
            guard !finished else { return }
            finished = true
            connection.stateUpdateHandler = nil
            connection.cancel()
            continuation.resume(with: result)
        }
    }

    private static func parse(_ data: Data, complete: Bool) throws -> Response? {
        let separator = Data("\r\n\r\n".utf8)
        guard let boundary = data.range(of: separator) else {
            if complete { throw Failure.invalidResponse }
            return nil
        }
        guard let headerText = String(data: data[..<boundary.lowerBound], encoding: .isoLatin1) else {
            throw Failure.invalidResponse
        }
        let lines = headerText.components(separatedBy: "\r\n")
        let statusParts = lines[0].split(separator: " ", maxSplits: 2)
        guard statusParts.count >= 2, let statusCode = Int(statusParts[1]) else {
            throw Failure.invalidResponse
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let rawBody = Data(data[boundary.upperBound...])
        let responseBody: Data
        if headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
            guard let decoded = try decodeChunks(rawBody, complete: complete) else { return nil }
            responseBody = decoded
        } else if let lengthText = headers["content-length"], let length = Int(lengthText) {
            guard length >= 0 else { throw Failure.invalidResponse }
            guard rawBody.count >= length else {
                if complete { throw Failure.invalidResponse }
                return nil
            }
            responseBody = Data(rawBody.prefix(length))
        } else {
            guard complete else { return nil }
            responseBody = rawBody
        }
        return Response(statusCode: statusCode, headers: headers, body: responseBody)
    }

    private static func decodeChunks(_ data: Data, complete: Bool) throws -> Data? {
        let lineEnd = Data("\r\n".utf8)
        var cursor = 0
        var decoded = Data()
        while cursor < data.count {
            guard let boundary = data.range(of: lineEnd, in: cursor..<data.count) else {
                if complete { throw Failure.invalidResponse }
                return nil
            }
            guard let sizeText = String(data: data[cursor..<boundary.lowerBound], encoding: .ascii),
                  let sizePart = sizeText.split(separator: ";", maxSplits: 1).first,
                  let size = Int(sizePart, radix: 16) else { throw Failure.invalidResponse }
            cursor = boundary.upperBound
            if size == 0 { return decoded }
            guard size <= data.count - cursor, cursor + size + 2 <= data.count else {
                if complete { throw Failure.invalidResponse }
                return nil
            }
            guard data[cursor + size] == 13, data[cursor + size + 1] == 10 else { throw Failure.invalidResponse }
            decoded.append(data[cursor..<cursor + size])
            cursor += size + 2
        }
        if complete { throw Failure.invalidResponse }
        return nil
    }
}
