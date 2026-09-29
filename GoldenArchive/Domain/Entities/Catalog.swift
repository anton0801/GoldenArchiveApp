//
//  Catalog.swift
//  GoldenArchive
//
//  Domain layer — reference suggestions from catalog sources. A candidate
//  is only ever a metadata suggestion; the user confirms identification.
//

import Foundation

struct CatalogQuery: Hashable {
    var text: String = ""
    var kind: ItemKind = .coin
    var country: String = ""
    var year: Int? = nil
    var denomination: String = ""
    var mint: String = ""
    var material: String = ""

    var isEmpty: Bool {
        text.isBlank && country.isBlank && year == nil && denomination.isBlank && mint.isBlank && material.isBlank
    }

    /// Free text sent to remote sources.
    var combinedText: String {
        [text, country, denomination].map(\.trimmed).filter { !$0.isEmpty }.joined(separator: " ")
    }

    var attributes: ExpectedAttributes {
        ExpectedAttributes(country: country, year: year, denomination: denomination, mint: mint, material: material)
    }
}

struct CatalogCandidate: Identifiable, Hashable {
    /// "<source>:<external id>"
    let id: String
    var sourceName: String
    var externalID: String
    var title: String
    var country: String
    var minYear: Int?
    var maxYear: Int?
    var denomination: String
    var mints: [String]
    var material: String
    var diameterMM: Double?
    var weightGrams: Double?
    var edge: String
    var imageURL: URL?
    var imageCredit: String?
    var pageURL: URL?
    var hasDetails: Bool

    var yearRangeText: String {
        switch (minYear, maxYear) {
        case let (min?, max?) where min == max: return YearText.display(min)
        case let (min?, max?): return "\(YearText.display(min))–\(YearText.display(max))"
        case let (min?, nil): return "\(YearText.display(min))–"
        case let (nil, max?): return "–\(YearText.display(max))"
        default: return ""
        }
    }
}

enum MatchStrength: Int, Comparable {
    case weak = 0
    case partial = 1
    case strong = 2

    /// Labels describe metadata agreement only — never an expert identification.
    var label: String {
        switch self {
        case .strong: return "Strong metadata match"
        case .partial: return "Partial metadata match"
        case .weak: return "Weak metadata match"
        }
    }

    static func < (lhs: MatchStrength, rhs: MatchStrength) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct AttributeDifference: Hashable, Identifiable {
    var field: String
    var entered: String
    var reference: String
    var id: String { field }
}

struct CandidateAssessment: Hashable {
    var strength: MatchStrength
    var matchedFields: [String]
    var differences: [AttributeDifference]
    var score: Double
}

struct CatalogSearchResult {
    var candidates: [CatalogCandidate]
    var sourcesQueried: [String]
    var sourceErrors: [String: String]

    static let empty = CatalogSearchResult(candidates: [], sourcesQueried: [], sourceErrors: [:])
}

enum CatalogError: LocalizedError {
    case missingAPIKey
    case invalidAPIKey
    case rateLimited
    case offline
    case server(Int)
    case decoding
    case unsupported

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Add a Numista API key in Settings to use this source."
        case .invalidAPIKey: return "The catalog rejected the API key. Check it in Settings."
        case .rateLimited: return "The catalog is limiting requests right now. Try again later."
        case .offline: return "No internet connection."
        case .server(let code): return "The catalog responded with an error (\(code))."
        case .decoding: return "The catalog response could not be read."
        case .unsupported: return "This source has no further details."
        }
    }
}
