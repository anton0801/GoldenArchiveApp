//
//  CoinSet.swift
//  GoldenArchive
//
//  Domain layer — an album or set: ordered slots that are either filled by
//  a real item from the archive or still missing.
//

import Foundation

struct SetSlot: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var expected: ExpectedAttributes
    var linkedCoinID: UUID?
    var isOptional: Bool
    /// How many physical pieces this slot asks for (usually 1).
    var quantityNeeded: Int
    var linkedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        expected: ExpectedAttributes = ExpectedAttributes(),
        linkedCoinID: UUID? = nil,
        isOptional: Bool = false,
        quantityNeeded: Int = 1,
        linkedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.expected = expected
        self.linkedCoinID = linkedCoinID
        self.isOptional = isOptional
        self.quantityNeeded = quantityNeeded
        self.linkedAt = linkedAt
    }

    var displayTitle: String {
        if !title.isBlank { return title }
        let summary = expected.summary
        return summary.isEmpty ? "Untitled slot" : summary
    }
}

struct CoinSet: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var collectionID: UUID?
    var note: String
    var slots: [SetSlot]
    var templateName: String?
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        collectionID: UUID? = nil,
        note: String = "",
        slots: [SetSlot] = [],
        templateName: String? = nil,
        archivedAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.collectionID = collectionID
        self.note = note
        self.slots = slots
        self.templateName = templateName
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isArchived: Bool { archivedAt != nil }
}

struct TemplateSlot: Codable, Hashable {
    var title: String
    var expected: ExpectedAttributes
    var isOptional: Bool
    var quantityNeeded: Int
}

struct SetTemplate: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var summary: String
    var slots: [TemplateSlot]
    var isBuiltIn: Bool
    var createdAt: Date
}
