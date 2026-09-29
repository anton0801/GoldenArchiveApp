//
//  LocalRepositories.swift
//  GoldenArchive
//
//  Data layer — protocol implementations over the local archive database.
//

import Foundation
import Combine

class LocalRepository {
    let db: ArchiveDatabase
    init(db: ArchiveDatabase) { self.db = db }
}

final class LocalChangeObserver: LocalRepository, ArchiveChangeObserving {
    var changes: AnyPublisher<Void, Never> { db.changes }
}

final class LocalCoinRepository: LocalRepository, CoinRepository {
    func coins(includeArchived: Bool) -> [Coin] {
        db.read { snapshot in includeArchived ? snapshot.coins : snapshot.coins.filter { !$0.isArchived } }
    }
    func coin(id: UUID) -> Coin? { db.read { $0.coins.first { $0.id == id } } }
    func save(_ coin: Coin) { db.mutate { $0.coins.upsert(coin) } }
    func save(_ coins: [Coin]) { db.mutate { $0.coins.upsert(coins) } }
    func deleteCoin(id: UUID) { db.mutate { $0.coins.removeAll { $0.id == id } } }
}

final class LocalCollectionRepository: LocalRepository, CollectionRepository {
    func collections(includeArchived: Bool) -> [CoinCollection] {
        db.read { snapshot in
            (includeArchived ? snapshot.collections : snapshot.collections.filter { !$0.isArchived })
                .sorted { $0.sortIndex < $1.sortIndex }
        }
    }
    func collection(id: UUID) -> CoinCollection? { db.read { $0.collections.first { $0.id == id } } }
    func save(_ collection: CoinCollection) { db.mutate { $0.collections.upsert(collection) } }
    func save(_ collections: [CoinCollection]) { db.mutate { $0.collections.upsert(collections) } }
    func deleteCollection(id: UUID) { db.mutate { $0.collections.removeAll { $0.id == id } } }
}

final class LocalSetRepository: LocalRepository, SetRepository {
    func sets(includeArchived: Bool) -> [CoinSet] {
        db.read { snapshot in includeArchived ? snapshot.sets : snapshot.sets.filter { !$0.isArchived } }
    }
    func set(id: UUID) -> CoinSet? { db.read { $0.sets.first { $0.id == id } } }
    func save(_ set: CoinSet) { db.mutate { $0.sets.upsert(set) } }
    func save(_ sets: [CoinSet]) { db.mutate { $0.sets.upsert(sets) } }
    func deleteSet(id: UUID) { db.mutate { $0.sets.removeAll { $0.id == id } } }

    func userTemplates() -> [SetTemplate] { db.read { $0.templates.sorted { $0.createdAt > $1.createdAt } } }
    func save(_ template: SetTemplate) { db.mutate { $0.templates.upsert(template) } }
    func deleteTemplate(id: UUID) { db.mutate { $0.templates.removeAll { $0.id == id } } }
}

final class LocalConditionRepository: LocalRepository, ConditionRepository {
    func observations(coinID: UUID?) -> [ConditionObservation] {
        db.read { snapshot in
            snapshot.observations
                .filter { coinID == nil || $0.coinID == coinID }
                .sorted { $0.observedOn > $1.observedOn }
        }
    }
    func observation(id: UUID) -> ConditionObservation? { db.read { $0.observations.first { $0.id == id } } }
    func save(_ observation: ConditionObservation) { db.mutate { $0.observations.upsert(observation) } }
    func deleteObservation(id: UUID) { db.mutate { $0.observations.removeAll { $0.id == id } } }
}

final class LocalDocumentRepository: LocalRepository, DocumentRepository {
    func documents() -> [ProvenanceDocument] {
        db.read { $0.documents.sorted { ($0.date ?? $0.createdAt) > ($1.date ?? $1.createdAt) } }
    }
    func document(id: UUID) -> ProvenanceDocument? { db.read { $0.documents.first { $0.id == id } } }
    func save(_ document: ProvenanceDocument) { db.mutate { $0.documents.upsert(document) } }
    func save(_ documents: [ProvenanceDocument]) { db.mutate { $0.documents.upsert(documents) } }
    func deleteDocument(id: UUID) { db.mutate { $0.documents.removeAll { $0.id == id } } }
}

final class LocalDuplicateRepository: LocalRepository, DuplicateRepository {
    func groups() -> [DuplicateGroup] { db.read { $0.duplicateGroups.sorted { $0.updatedAt > $1.updatedAt } } }
    func group(id: UUID) -> DuplicateGroup? { db.read { $0.duplicateGroups.first { $0.id == id } } }
    func save(_ group: DuplicateGroup) { db.mutate { $0.duplicateGroups.upsert(group) } }
    func deleteGroup(id: UUID) { db.mutate { $0.duplicateGroups.removeAll { $0.id == id } } }
}

final class LocalWishRepository: LocalRepository, WishRepository {
    func wishes() -> [WishItem] { db.read { $0.wishes } }
    func wish(id: UUID) -> WishItem? { db.read { $0.wishes.first { $0.id == id } } }
    func save(_ wish: WishItem) { db.mutate { $0.wishes.upsert(wish) } }
    func save(_ wishes: [WishItem]) { db.mutate { $0.wishes.upsert(wishes) } }
    func deleteWish(id: UUID) { db.mutate { $0.wishes.removeAll { $0.id == id } } }
}

final class LocalGoalRepository: LocalRepository, GoalRepository {
    func goals() -> [CollectionGoal] { db.read { $0.goals.sorted { $0.createdAt > $1.createdAt } } }
    func goal(id: UUID) -> CollectionGoal? { db.read { $0.goals.first { $0.id == id } } }
    func save(_ goal: CollectionGoal) { db.mutate { $0.goals.upsert(goal) } }
    func deleteGoal(id: UUID) { db.mutate { $0.goals.removeAll { $0.id == id } } }
}

final class LocalValueNoteRepository: LocalRepository, ValueNoteRepository {
    func valueNotes(coinID: UUID?) -> [ValueNote] {
        db.read { snapshot in
            snapshot.valueNotes
                .filter { coinID == nil || $0.coinID == coinID }
                .sorted { $0.valueDate > $1.valueDate }
        }
    }
    func save(_ note: ValueNote) { db.mutate { $0.valueNotes.upsert(note) } }
    func deleteValueNote(id: UUID) { db.mutate { $0.valueNotes.removeAll { $0.id == id } } }
}

final class LocalExhibitionRepository: LocalRepository, ExhibitionRepository {
    func exhibitions() -> [Exhibition] { db.read { $0.exhibitions.sorted { $0.updatedAt > $1.updatedAt } } }
    func exhibition(id: UUID) -> Exhibition? { db.read { $0.exhibitions.first { $0.id == id } } }
    func save(_ exhibition: Exhibition) { db.mutate { $0.exhibitions.upsert(exhibition) } }
    func deleteExhibition(id: UUID) { db.mutate { $0.exhibitions.removeAll { $0.id == id } } }
}

final class LocalSettingsRepository: LocalRepository, SettingsRepository {
    func settings() -> AppSettings { db.read { $0.settings } }
    func update(_ change: (inout AppSettings) -> Void) {
        var settings = db.read { $0.settings }
        change(&settings)
        db.mutate { $0.settings = settings }
    }
}

final class LocalMaintenanceRepository: LocalRepository, ArchiveMaintenanceRepository {
    func snapshot() -> ArchiveSnapshot { db.read { $0 } }
    func replaceSnapshot(_ snapshot: ArchiveSnapshot) throws { try db.replace(with: snapshot) }
    var lastLoadIssue: String? { db.loadIssue }
}
