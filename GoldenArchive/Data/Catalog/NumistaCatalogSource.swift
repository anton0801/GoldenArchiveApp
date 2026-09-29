//
//  NumistaCatalogSource.swift
//  GoldenArchive
//
//  Data layer — optional remote reference source (Numista API v3). It is
//  used only when the user enables it and supplies their own API key.
//  Results are suggestions; images keep their source attribution.
//

import Foundation

protocol CatalogSource {
    var name: String { get }
    func search(_ query: CatalogQuery) async throws -> [CatalogCandidate]
    func details(for candidate: CatalogCandidate) async throws -> CatalogCandidate
}

final class NumistaCatalogSource: CatalogSource {
    let name = "Numista"

    private let client: HTTPClient
    private let apiKey: () -> String?
    /// Set on the main thread before each search (settings live on main).
    var language = "en"
    private let baseURL = URL(string: "https://api.numista.com/v3")!

    init(client: HTTPClient, apiKey: @escaping () -> String?) {
        self.client = client
        self.apiKey = apiKey
    }

    func search(_ query: CatalogQuery) async throws -> [CatalogCandidate] {
        guard let key = apiKey(), !key.isEmpty else { throw CatalogError.missingAPIKey }
        var components = URLComponents(url: baseURL.appendingPathComponent("types"), resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "q", value: query.combinedText),
            URLQueryItem(name: "count", value: "20"),
            URLQueryItem(name: "lang", value: language),
            URLQueryItem(name: "category", value: query.kind == .coin ? "coin" : "exonumia")
        ]
        if let year = query.year { items.append(URLQueryItem(name: "year", value: "\(year)")) }
        components.queryItems = items
        guard let url = components.url else { throw CatalogError.decoding }

        let data = try await perform(url, key: key)
        guard let response = try? JSONDecoder().decode(NumistaSearchResponse.self, from: data) else { throw CatalogError.decoding }
        return response.types.map { type in
            CatalogCandidate(
                id: "\(name):\(type.id)",
                sourceName: name,
                externalID: "\(type.id)",
                title: type.title,
                country: type.issuer?.name ?? "",
                minYear: type.minYear,
                maxYear: type.maxYear,
                denomination: "",
                mints: [],
                material: "",
                diameterMM: nil,
                weightGrams: nil,
                edge: "",
                imageURL: type.obverseThumbnail.flatMap(URL.init(string:)),
                imageCredit: "Image: Numista",
                pageURL: URL(string: "https://en.numista.com/catalogue/pieces\(type.id).html"),
                hasDetails: false
            )
        }
    }

    func details(for candidate: CatalogCandidate) async throws -> CatalogCandidate {
        guard let key = apiKey(), !key.isEmpty else { throw CatalogError.missingAPIKey }
        var components = URLComponents(url: baseURL.appendingPathComponent("types/\(candidate.externalID)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "lang", value: language)]
        guard let url = components.url else { throw CatalogError.decoding }
        let data = try await perform(url, key: key)
        guard let detail = try? JSONDecoder().decode(NumistaTypeDetail.self, from: data) else { throw CatalogError.decoding }

        var updated = candidate
        updated.title = detail.title ?? candidate.title
        updated.country = detail.issuer?.name ?? candidate.country
        updated.minYear = detail.minYear ?? candidate.minYear
        updated.maxYear = detail.maxYear ?? candidate.maxYear
        updated.denomination = detail.value?.text ?? ""
        updated.material = detail.composition?.text ?? ""
        updated.diameterMM = detail.size
        updated.weightGrams = detail.weight
        updated.edge = detail.edge?.description ?? ""
        updated.mints = detail.mints?.compactMap(\.name) ?? []
        if let picture = detail.obverse?.picture ?? detail.obverse?.thumbnail, let url = URL(string: picture) {
            updated.imageURL = url
        }
        if let copyright = detail.obverse?.pictureCopyright, !copyright.isBlank {
            updated.imageCredit = "Image: \(copyright) via Numista"
        }
        if let page = detail.url.flatMap(URL.init(string:)) { updated.pageURL = page }
        updated.hasDetails = true
        return updated
    }

    private func perform(_ url: URL, key: String) async throws -> Data {
        let (data, response) = try await client.get(url, headers: ["Numista-API-Key": key, "Accept": "application/json"])
        switch response.statusCode {
        case 200: return data
        case 401, 403: throw CatalogError.invalidAPIKey
        case 429: throw CatalogError.rateLimited
        default: throw CatalogError.server(response.statusCode)
        }
    }
}

// MARK: - DTOs

private struct NumistaSearchResponse: Decodable {
    var types: [NumistaTypeSummary]

    enum CodingKeys: String, CodingKey { case types }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        types = (try? container.decodeIfPresent([NumistaTypeSummary].self, forKey: .types)) ?? []
    }
}

private struct NumistaIssuer: Decodable {
    var name: String?
}

private struct NumistaTypeSummary: Decodable {
    var id: Int
    var title: String
    var issuer: NumistaIssuer?
    var minYear: Int?
    var maxYear: Int?
    var obverseThumbnail: String?

    enum CodingKeys: String, CodingKey {
        case id, title, issuer
        case minYear = "min_year"
        case maxYear = "max_year"
        case obverseThumbnail = "obverse_thumbnail"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? "Untitled type"
        issuer = try? c.decodeIfPresent(NumistaIssuer.self, forKey: .issuer)
        minYear = try? c.decodeIfPresent(Int.self, forKey: .minYear)
        maxYear = try? c.decodeIfPresent(Int.self, forKey: .maxYear)
        obverseThumbnail = try? c.decodeIfPresent(String.self, forKey: .obverseThumbnail)
    }
}

private struct NumistaTypeDetail: Decodable {
    struct Value: Decodable { var text: String? }
    struct Composition: Decodable { var text: String? }
    struct Side: Decodable {
        var description: String?
        var picture: String?
        var thumbnail: String?
        var pictureCopyright: String?

        enum CodingKeys: String, CodingKey {
            case description, picture, thumbnail
            case pictureCopyright = "picture_copyright"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            description = try? c.decodeIfPresent(String.self, forKey: .description)
            picture = try? c.decodeIfPresent(String.self, forKey: .picture)
            thumbnail = try? c.decodeIfPresent(String.self, forKey: .thumbnail)
            pictureCopyright = try? c.decodeIfPresent(String.self, forKey: .pictureCopyright)
        }
    }
    struct Mint: Decodable { var name: String? }

    var title: String?
    var url: String?
    var issuer: NumistaIssuer?
    var minYear: Int?
    var maxYear: Int?
    var value: Value?
    var composition: Composition?
    var weight: Double?
    var size: Double?
    var edge: Side?
    var obverse: Side?
    var mints: [Mint]?

    enum CodingKeys: String, CodingKey {
        case title, url, issuer, value, composition, weight, size, edge, obverse, mints
        case minYear = "min_year"
        case maxYear = "max_year"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        url = try? c.decodeIfPresent(String.self, forKey: .url)
        issuer = try? c.decodeIfPresent(NumistaIssuer.self, forKey: .issuer)
        minYear = try? c.decodeIfPresent(Int.self, forKey: .minYear)
        maxYear = try? c.decodeIfPresent(Int.self, forKey: .maxYear)
        value = try? c.decodeIfPresent(Value.self, forKey: .value)
        composition = try? c.decodeIfPresent(Composition.self, forKey: .composition)
        weight = try? c.decodeIfPresent(Double.self, forKey: .weight)
        size = try? c.decodeIfPresent(Double.self, forKey: .size)
        edge = try? c.decodeIfPresent(Side.self, forKey: .edge)
        obverse = try? c.decodeIfPresent(Side.self, forKey: .obverse)
        mints = try? c.decodeIfPresent([Mint].self, forKey: .mints)
    }
}
