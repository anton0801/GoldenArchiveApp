//
//  Coin.swift
//  GoldenArchive
//
//  Domain layer — a physical item in the user's collection: a coin,
//  a commemorative token or a medal. Every attribute is entered or
//  confirmed by the user; catalog data is only ever a reference.
//

import Foundation

enum ItemKind: String, Codable, CaseIterable, Identifiable {
    case coin
    case token
    case medal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .coin: return "Coin"
        case .token: return "Token"
        case .medal: return "Medal"
        }
    }

    var pluralTitle: String {
        switch self {
        case .coin: return "Coins"
        case .token: return "Tokens"
        case .medal: return "Medals"
        }
    }
}

enum PhotoSide: String, Codable, CaseIterable, Identifiable {
    case obverse
    case reverse
    case edge
    case detail

    var id: String { rawValue }

    var title: String {
        switch self {
        case .obverse: return "Obverse"
        case .reverse: return "Reverse"
        case .edge: return "Edge"
        case .detail: return "Detail"
        }
    }

    /// Order used when presenting a coin's photos.
    var sortOrder: Int {
        switch self {
        case .obverse: return 0
        case .reverse: return 1
        case .edge: return 2
        case .detail: return 3
        }
    }
}

/// Normalised crop rectangle (0...1 in the rotated original's space).
struct CropRegion: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let full = CropRegion(x: 0, y: 0, width: 1, height: 1)
}

/// A user photo. The original file is never modified; a crop is kept as a
/// separate file so the user can always go back to what the camera saw.
struct CoinPhoto: Identifiable, Codable, Hashable {
    let id: UUID
    var side: PhotoSide
    var original: StoredFile
    var cropped: StoredFile?
    var crop: CropRegion?
    var quarterTurns: Int
    var capturedAt: Date
    var quality: PhotoQualityReport?

    init(
        id: UUID = UUID(),
        side: PhotoSide,
        original: StoredFile,
        cropped: StoredFile? = nil,
        crop: CropRegion? = nil,
        quarterTurns: Int = 0,
        capturedAt: Date,
        quality: PhotoQualityReport? = nil
    ) {
        self.id = id
        self.side = side
        self.original = original
        self.cropped = cropped
        self.crop = crop
        self.quarterTurns = quarterTurns
        self.capturedAt = capturedAt
        self.quality = quality
    }

    /// The file shown in the UI: the user's crop when there is one.
    var displayFile: StoredFile { cropped ?? original }

    var allFiles: [StoredFile] { [original] + (cropped.map { [$0] } ?? []) }
}

/// Measured facts about a photo. It describes the picture, never the coin.
struct PhotoQualityReport: Codable, Hashable {
    var pixelWidth: Int
    var pixelHeight: Int
    /// Share of the centre area that is blown-out highlight (0...1).
    var glareFraction: Double
    /// Mean luminance (0...1).
    var brightness: Double
    /// Edge-energy estimate; low values mean the photo looks soft.
    var sharpness: Double

    var hasGlare: Bool { glareFraction >= 0.035 }
    var isDark: Bool { brightness < 0.18 }
    var isSoft: Bool { sharpness < 0.018 }
    var isLowResolution: Bool { min(pixelWidth, pixelHeight) < 600 }

    var notes: [String] {
        var notes: [String] = []
        if hasGlare { notes.append("Glare covers about \(Int((glareFraction * 100).rounded()))% of the centre. Tilt the light or the coin.") }
        if isDark { notes.append("The photo is dark. Add diffuse light.") }
        if isSoft { notes.append("The photo looks soft. Hold steady and refocus.") }
        if isLowResolution { notes.append("Low resolution (\(pixelWidth)×\(pixelHeight)). Move closer or use a larger source.") }
        return notes
    }

    var summary: String {
        notes.isEmpty ? "\(pixelWidth)×\(pixelHeight) px · no glare or blur detected" : notes.joined(separator: " ")
    }
}

/// Where a catalog suggestion came from, kept for the user's reference.
struct CatalogReference: Codable, Hashable {
    var sourceName: String
    var externalID: String
    var title: String
    var url: String?
    var retrievedAt: Date
    var matchLabel: String
}

struct Coin: Identifiable, Codable, Hashable {
    let id: UUID
    var kind: ItemKind
    var name: String
    var country: String
    var year: Int?
    var denomination: String
    var mint: String
    var material: String
    var diameterMM: Double?
    var weightGrams: Double?
    var edge: String
    var quantity: Int
    var collectionID: UUID?
    /// The user's own grade or condition wording — not a professional grade.
    var condition: String
    var notes: String
    var tags: [String]
    var photos: [CoinPhoto]
    var catalogReference: CatalogReference?
    var needsReview: Bool
    var reviewReason: String
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var history: [ChangeEntry]

    init(
        id: UUID = UUID(),
        kind: ItemKind = .coin,
        name: String = "",
        country: String = "",
        year: Int? = nil,
        denomination: String = "",
        mint: String = "",
        material: String = "",
        diameterMM: Double? = nil,
        weightGrams: Double? = nil,
        edge: String = "",
        quantity: Int = 1,
        collectionID: UUID? = nil,
        condition: String = "",
        notes: String = "",
        tags: [String] = [],
        photos: [CoinPhoto] = [],
        catalogReference: CatalogReference? = nil,
        needsReview: Bool = false,
        reviewReason: String = "",
        archivedAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date,
        history: [ChangeEntry] = []
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.country = country
        self.year = year
        self.denomination = denomination
        self.mint = mint
        self.material = material
        self.diameterMM = diameterMM
        self.weightGrams = weightGrams
        self.edge = edge
        self.quantity = quantity
        self.collectionID = collectionID
        self.condition = condition
        self.notes = notes
        self.tags = tags
        self.photos = photos
        self.catalogReference = catalogReference
        self.needsReview = needsReview
        self.reviewReason = reviewReason
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.history = history
    }

    var isArchived: Bool { archivedAt != nil }

    var displayName: String { name.isBlank ? "Untitled item" : name }

    /// "United States · 1921 · 1 Dollar"
    var subtitle: String {
        [country, year.map(YearText.display) ?? "", denomination]
            .map { $0.trimmed }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var sortedPhotos: [CoinPhoto] {
        photos.sorted { lhs, rhs in
            lhs.side.sortOrder == rhs.side.sortOrder
                ? lhs.capturedAt < rhs.capturedAt
                : lhs.side.sortOrder < rhs.side.sortOrder
        }
    }

    var primaryPhoto: CoinPhoto? { sortedPhotos.first }

    var attributes: ExpectedAttributes {
        ExpectedAttributes(country: country, year: year, denomination: denomination, mint: mint, material: material)
    }

    var allFiles: [StoredFile] { photos.flatMap(\.allFiles) }

    var searchText: String {
        ([name, country, year.map(YearText.display) ?? "", denomination, mint, material, edge, condition, notes, kind.title]
            + tags).joined(separator: " ").normalizedKey
    }
}
