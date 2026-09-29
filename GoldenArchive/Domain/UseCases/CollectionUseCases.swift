//
//  CollectionUseCases.swift
//  GoldenArchive
//
//  Domain layer — collections. Deleting a collection never deletes items:
//  they are either moved or kept as Unsorted.
//

import Foundation

enum CollectionDeletionChoice: Hashable {
    case moveItems(to: UUID)
    case keepUnsorted
}

struct CollectionUseCase {
    let collections: CollectionRepository
    let coins: CoinRepository
    let sets: SetRepository
    let goals: GoalRepository
    let clock: Clock

    @discardableResult
    func create(name: String, theme: CollectionTheme, tags: [String], completionNote: String) -> CoinCollection {
        let now = clock.now
        let nextIndex = (collections.collections(includeArchived: true).map(\.sortIndex).max() ?? -1) + 1
        let collection = CoinCollection(
            name: name.trimmed,
            theme: theme,
            tags: tags.cleanedTags(),
            completionNote: completionNote.trimmed,
            sortIndex: nextIndex,
            createdAt: now,
            updatedAt: now
        )
        collections.save(collection)
        return collection
    }

    func update(_ collection: CoinCollection) {
        var copy = collection
        copy.name = copy.name.trimmed
        copy.tags = copy.tags.cleanedTags()
        copy.updatedAt = clock.now
        collections.save(copy)
    }

    func rename(id: UUID, to name: String) {
        guard var collection = collections.collection(id: id), !name.isBlank else { return }
        collection.name = name
        update(collection)
    }

    func setCover(id: UUID, cover: CoverReference?) {
        guard var collection = collections.collection(id: id) else { return }
        collection.cover = cover
        update(collection)
    }

    func reorder(_ ordered: [CoinCollection]) {
        let updated = ordered.enumerated().map { index, collection -> CoinCollection in
            var copy = collection
            copy.sortIndex = index
            return copy
        }
        collections.save(updated)
    }

    func archive(id: UUID, archived: Bool) {
        guard var collection = collections.collection(id: id) else { return }
        collection.archivedAt = archived ? clock.now : nil
        update(collection)
    }

    /// Creates an empty copy: same theme, tags and sorting, plus copies of the
    /// collection's sets with every slot unlinked. No items are copied.
    @discardableResult
    func duplicateStructure(id: UUID) -> CoinCollection? {
        guard let source = collections.collection(id: id) else { return nil }
        let now = clock.now
        let nextIndex = (collections.collections(includeArchived: true).map(\.sortIndex).max() ?? -1) + 1
        let copy = CoinCollection(
            name: "\(source.name) (structure)",
            theme: source.theme,
            tags: source.tags,
            completionNote: "",
            sortIndex: nextIndex,
            itemSort: source.itemSort,
            createdAt: now,
            updatedAt: now
        )
        collections.save(copy)
        let copiedSets = sets.sets(includeArchived: false).filter { $0.collectionID == id }.map { set in
            CoinSet(
                name: set.name,
                collectionID: copy.id,
                note: set.note,
                slots: set.slots.map { SetSlot(title: $0.title, expected: $0.expected, isOptional: $0.isOptional, quantityNeeded: $0.quantityNeeded) },
                templateName: set.templateName,
                createdAt: now,
                updatedAt: now
            )
        }
        if !copiedSets.isEmpty { sets.save(copiedSets) }
        return copy
    }

    func itemCount(collectionID: UUID) -> Int {
        coins.coins(includeArchived: false).filter { $0.collectionID == collectionID }.count
    }

    func delete(id: UUID, choice: CollectionDeletionChoice) {
        guard let collection = collections.collection(id: id) else { return }
        let now = clock.now
        let target: UUID?
        let targetName: String
        switch choice {
        case .moveItems(let destination):
            target = destination
            targetName = collections.collection(id: destination)?.name ?? "another collection"
        case .keepUnsorted:
            target = nil
            targetName = "Unsorted"
        }
        let moved: [Coin] = coins.coins(includeArchived: true).compactMap { coin in
            guard coin.collectionID == id else { return nil }
            var copy = coin
            copy.collectionID = target
            copy.updatedAt = now
            copy.history.append(ChangeEntry(date: now, summary: "Collection “\(collection.name)” was deleted; moved to \(targetName)."))
            return copy
        }
        if !moved.isEmpty { coins.save(moved) }

        let detachedSets: [CoinSet] = sets.sets(includeArchived: true).compactMap { set in
            guard set.collectionID == id else { return nil }
            var copy = set
            copy.collectionID = target
            copy.updatedAt = now
            return copy
        }
        if !detachedSets.isEmpty { sets.save(detachedSets) }

        for goal in goals.goals() {
            if case .itemCount(let collectionID, let count) = goal.target, collectionID == id {
                var copy = goal
                copy.target = .itemCount(collectionID: target, target: count)
                copy.updatedAt = now
                goals.save(copy)
            }
        }
        collections.deleteCollection(id: id)
    }

    static func sorted(_ coins: [Coin], by order: ItemSortOrder) -> [Coin] {
        switch order {
        case .recent:
            return coins.sorted { $0.createdAt > $1.createdAt }
        case .name:
            return coins.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .year:
            return coins.sorted { ($0.year ?? Int.max) < ($1.year ?? Int.max) }
        case .country:
            return coins.sorted {
                $0.country.localizedCaseInsensitiveCompare($1.country) == .orderedAscending
            }
        }
    }
}
