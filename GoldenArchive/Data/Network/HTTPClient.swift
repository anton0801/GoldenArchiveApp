//
//  HTTPClient.swift
//  GoldenArchive
//

import Foundation

protocol HTTPClient {
    func get(_ url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse)
}

final class URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .useProtocolCachePolicy
        session = URLSession(configuration: configuration)
    }

    func get(_ url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost].contains(error.code) {
            throw CatalogError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw CatalogError.decoding }
        return (data, http)
    }
}
