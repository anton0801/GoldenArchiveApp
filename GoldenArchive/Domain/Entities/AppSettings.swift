//
//  AppSettings.swift
//  GoldenArchive
//

import Foundation

enum MeasurementUnits: String, Codable, CaseIterable, Identifiable {
    case metric
    case imperial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .metric: return "Millimetres & grams"
        case .imperial: return "Inches & ounces"
        }
    }
}

struct AppSettings: Codable, Hashable {
    var hasCompletedOnboarding: Bool
    var defaultCurrency: String
    var units: MeasurementUnits
    var offlineReferenceEnabled: Bool
    var numistaEnabled: Bool
    var catalogLanguage: String
    var collectionListSort: CollectionListSort

    static var `default`: AppSettings {
        AppSettings(
            hasCompletedOnboarding: false,
            defaultCurrency: Locale.current.currencyCode ?? "USD",
            units: Locale.current.usesMetricSystem ? .metric : .imperial,
            offlineReferenceEnabled: true,
            numistaEnabled: false,
            catalogLanguage: "en",
            collectionListSort: .manual
        )
    }
}

/// Everything the user owns, as one value. The data layer persists it and
/// the backup feature exports it.
struct ArchiveSnapshot: Codable, Hashable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = ArchiveSnapshot.currentSchemaVersion
    var coins: [Coin] = []
    var collections: [CoinCollection] = []
    var sets: [CoinSet] = []
    var templates: [SetTemplate] = []
    var observations: [ConditionObservation] = []
    var documents: [ProvenanceDocument] = []
    var duplicateGroups: [DuplicateGroup] = []
    var wishes: [WishItem] = []
    var goals: [CollectionGoal] = []
    var valueNotes: [ValueNote] = []
    var exhibitions: [Exhibition] = []
    var settings: AppSettings = .default

    /// Every file referenced by any record.
    var referencedFiles: [StoredFile] {
        coins.flatMap(\.allFiles)
            + observations.flatMap(\.closeUps)
            + documents.compactMap(\.file)
    }

    var isEmpty: Bool {
        coins.isEmpty && collections.isEmpty && sets.isEmpty && templates.isEmpty
            && observations.isEmpty && documents.isEmpty && duplicateGroups.isEmpty
            && wishes.isEmpty && goals.isEmpty && valueNotes.isEmpty && exhibitions.isEmpty
    }
}
