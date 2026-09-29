//
//  Collection.swift
//  GoldenArchive
//
//  Domain layer — a themed group of items. Items point at a collection;
//  removing a collection never removes the items themselves.
//

import Foundation

enum CollectionTheme: String, Codable, CaseIterable, Identifiable {
    case country
    case era
    case material
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .country: return "Country"
        case .era: return "Era"
        case .material: return "Material"
        case .custom: return "Custom theme"
        }
    }

    var symbolName: String {
        switch self {
        case .country: return "globe.europe.africa.fill"
        case .era: return "hourglass"
        case .material: return "cube.fill"
        case .custom: return "sparkles"
        }
    }
}

enum ItemSortOrder: String, Codable, CaseIterable, Identifiable {
    case recent
    case name
    case year
    case country

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: return "Recently added"
        case .name: return "Name"
        case .year: return "Year"
        case .country: return "Country"
        }
    }
}

struct CoverReference: Codable, Hashable {
    var coinID: UUID
    var photoID: UUID
}

struct CoinCollection: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var theme: CollectionTheme
    var tags: [String]
    var cover: CoverReference?
    /// The user's own note about what is left to complete.
    var completionNote: String
    var sortIndex: Int
    var itemSort: ItemSortOrder
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        theme: CollectionTheme = .custom,
        tags: [String] = [],
        cover: CoverReference? = nil,
        completionNote: String = "",
        sortIndex: Int = 0,
        itemSort: ItemSortOrder = .recent,
        archivedAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.theme = theme
        self.tags = tags
        self.cover = cover
        self.completionNote = completionNote
        self.sortIndex = sortIndex
        self.itemSort = itemSort
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isArchived: Bool { archivedAt != nil }
}

enum CollectionListSort: String, Codable, CaseIterable, Identifiable {
    case manual
    case name
    case itemCount
    case recent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: return "Manual order"
        case .name: return "Name"
        case .itemCount: return "Item count"
        case .recent: return "Recently updated"
        }
    }
}
