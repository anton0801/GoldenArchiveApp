//
//  CoreTypes.swift
//  GoldenArchive
//
//  Domain layer — small value types shared by several entities.
//  The domain layer never imports UIKit or SwiftUI.
//

import Foundation

/// A file the user owns (photo, scan, receipt) kept in the local vault.
/// The record only stores a relative name; the data layer resolves it.
struct StoredFile: Codable, Hashable {
    var fileName: String
    var contentType: String
    var byteCount: Int
    var originalName: String?

    var isImage: Bool { contentType.hasPrefix("image/") }
    var isPDF: Bool { contentType == "application/pdf" }
}

/// A plain amount with an ISO currency code. Used for value notes and
/// optional purchase prices — never as a promise of a sale price.
struct MoneyAmount: Codable, Hashable {
    var amount: Decimal
    var currency: String
}

/// One line in the change history of a record.
struct ChangeEntry: Identifiable, Codable, Hashable {
    let id: UUID
    var date: Date
    var summary: String

    init(id: UUID = UUID(), date: Date, summary: String) {
        self.id = id
        self.date = date
        self.summary = summary
    }
}

/// Points to one slot of one set.
struct SlotReference: Codable, Hashable {
    var setID: UUID
    var slotID: UUID
}

/// Attributes a user expects for a set slot or a wanted item.
struct ExpectedAttributes: Codable, Hashable {
    var country: String = ""
    var year: Int? = nil
    var denomination: String = ""
    var mint: String = ""
    var material: String = ""

    var isEmpty: Bool {
        country.isBlank && year == nil && denomination.isBlank && mint.isBlank && material.isBlank
    }

    var summary: String {
        [country, year.map(YearText.display) ?? "", denomination, mint, material]
            .map { $0.trimmed }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

enum YearText {
    /// Negative years are stored for BC issues.
    static func display(_ year: Int) -> String {
        year < 0 ? "\(-year) BC" : "\(year)"
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var isBlank: Bool { trimmed.isEmpty }

    /// Lowercased, diacritic-insensitive form used for matching.
    var normalizedKey: String {
        trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
    }
}

extension Array where Element == String {
    /// Trims, drops blanks and removes case-insensitive duplicates while keeping order.
    func cleanedTags() -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in self {
            let tag = raw.trimmed
            guard !tag.isEmpty, seen.insert(tag.normalizedKey).inserted else { continue }
            result.append(tag)
        }
        return result
    }
}
