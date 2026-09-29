//
//  Repositories.swift
//  GoldenArchive
//
//  Domain layer — the contracts the data layer fulfils. Use cases and view
//  models only ever talk to these protocols.
//

import Foundation
import Combine

protocol ArchiveChangeObserving: AnyObject {
    /// Fires (coalesced, on the main thread) after any record changes.
    var changes: AnyPublisher<Void, Never> { get }
}

protocol CoinRepository: AnyObject {
    func coins(includeArchived: Bool) -> [Coin]
    func coin(id: UUID) -> Coin?
    func save(_ coin: Coin)
    func save(_ coins: [Coin])
    func deleteCoin(id: UUID)
}

protocol CollectionRepository: AnyObject {
    func collections(includeArchived: Bool) -> [CoinCollection]
    func collection(id: UUID) -> CoinCollection?
    func save(_ collection: CoinCollection)
    func save(_ collections: [CoinCollection])
    func deleteCollection(id: UUID)
}

protocol SetRepository: AnyObject {
    func sets(includeArchived: Bool) -> [CoinSet]
    func set(id: UUID) -> CoinSet?
    func save(_ set: CoinSet)
    func save(_ sets: [CoinSet])
    func deleteSet(id: UUID)

    func userTemplates() -> [SetTemplate]
    func save(_ template: SetTemplate)
    func deleteTemplate(id: UUID)
}

protocol ConditionRepository: AnyObject {
    func observations(coinID: UUID?) -> [ConditionObservation]
    func observation(id: UUID) -> ConditionObservation?
    func save(_ observation: ConditionObservation)
    func deleteObservation(id: UUID)
}

protocol DocumentRepository: AnyObject {
    func documents() -> [ProvenanceDocument]
    func document(id: UUID) -> ProvenanceDocument?
    func save(_ document: ProvenanceDocument)
    func save(_ documents: [ProvenanceDocument])
    func deleteDocument(id: UUID)
}

protocol DuplicateRepository: AnyObject {
    func groups() -> [DuplicateGroup]
    func group(id: UUID) -> DuplicateGroup?
    func save(_ group: DuplicateGroup)
    func deleteGroup(id: UUID)
}

protocol WishRepository: AnyObject {
    func wishes() -> [WishItem]
    func wish(id: UUID) -> WishItem?
    func save(_ wish: WishItem)
    func save(_ wishes: [WishItem])
    func deleteWish(id: UUID)
}

protocol GoalRepository: AnyObject {
    func goals() -> [CollectionGoal]
    func goal(id: UUID) -> CollectionGoal?
    func save(_ goal: CollectionGoal)
    func deleteGoal(id: UUID)
}

protocol ValueNoteRepository: AnyObject {
    func valueNotes(coinID: UUID?) -> [ValueNote]
    func save(_ note: ValueNote)
    func deleteValueNote(id: UUID)
}

protocol ExhibitionRepository: AnyObject {
    func exhibitions() -> [Exhibition]
    func exhibition(id: UUID) -> Exhibition?
    func save(_ exhibition: Exhibition)
    func deleteExhibition(id: UUID)
}

protocol SettingsRepository: AnyObject {
    func settings() -> AppSettings
    func update(_ change: (inout AppSettings) -> Void)
}

/// Secrets live outside the archive file (Keychain in the data layer).
protocol CredentialStore: AnyObject {
    func numistaAPIKey() -> String?
    func setNumistaAPIKey(_ key: String?)
}

/// Files the user owns: photos, crops, scans and documents.
protocol MediaRepository: AnyObject {
    func store(data: Data, contentType: String, originalName: String?) throws -> StoredFile
    /// Copies a picked file into the vault (off the main thread).
    func importFile(from url: URL, contentType: String, originalName: String?) async throws -> StoredFile
    func url(for file: StoredFile) -> URL
    func data(for file: StoredFile) -> Data?
    func exists(_ file: StoredFile) -> Bool
    func delete(_ file: StoredFile)
    func delete(_ files: [StoredFile])
    func allStoredFileNames() -> Set<String>
    func deleteFiles(named names: Set<String>)
    func deleteAllFiles()
}

protocol CatalogRepository: AnyObject {
    var activeSourceNames: [String] { get }
    func search(_ query: CatalogQuery) async -> CatalogSearchResult
    func details(for candidate: CatalogCandidate) async throws -> CatalogCandidate
}

/// Whole-archive access for backup, import and maintenance.
protocol ArchiveMaintenanceRepository: AnyObject {
    func snapshot() -> ArchiveSnapshot
    /// Replaces the archive in one step; either everything is replaced or nothing.
    func replaceSnapshot(_ snapshot: ArchiveSnapshot) throws
    var lastLoadIssue: String? { get }
}

protocol Clock {
    var now: Date { get }
}

struct SystemClock: Clock {
    var now: Date { Date() }
}

/// Measures and crops photos without altering colour or tone.
protocol PhotoProcessing {
    func analyze(_ data: Data) -> PhotoQualityReport?
    func crop(_ data: Data, quarterTurns: Int, region: CropRegion) -> Data?
}
