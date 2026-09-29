//
//  SummaryUseCases.swift
//  GoldenArchive
//
//  Domain layer — Home figures and Reports. Every number is derived from
//  the user's own records; nothing is estimated or invented.
//

import Foundation

// MARK: - Home

struct SetSummary: Identifiable, Hashable {
    var set: CoinSet
    var progress: SetProgress
    var id: UUID { self.set.id }
}

struct HomeSummary {
    var totalItems: Int
    var recordCount: Int
    var collectionCount: Int
    var overallSetProgress: SetProgress
    var incompleteSets: [SetSummary]
    var needsReview: [Coin]
    var duplicateExtras: Int
    var duplicateGroupCount: Int
    var recentItems: [Coin]
    var wantedCount: Int

    var isEmpty: Bool { recordCount == 0 }

    static let empty = HomeSummary(
        totalItems: 0, recordCount: 0, collectionCount: 0, overallSetProgress: .empty, incompleteSets: [],
        needsReview: [], duplicateExtras: 0, duplicateGroupCount: 0, recentItems: [], wantedCount: 0
    )
}

struct BuildHomeSummaryUseCase {
    let coins: CoinRepository
    let collections: CollectionRepository
    let sets: SetRepository
    let duplicates: DuplicateRepository
    let wishes: WishRepository

    func execute() -> HomeSummary {
        let allCoins = coins.coins(includeArchived: true)
        let active = allCoins.filter { !$0.isArchived }
        let activeSets = sets.sets(includeArchived: false)
        let groups = duplicates.groups()
        let calculator = SetProgressCalculator(coins: allCoins, sets: sets.sets(includeArchived: true), groups: groups)
        let summaries = activeSets.map { SetSummary(set: $0, progress: calculator.progress(for: $0)) }
        let overall = summaries.reduce(SetProgress.empty) { total, item in
            SetProgress(
                requiredTotal: total.requiredTotal + item.progress.requiredTotal,
                requiredCollected: total.requiredCollected + item.progress.requiredCollected,
                optionalTotal: total.optionalTotal + item.progress.optionalTotal,
                optionalCollected: total.optionalCollected + item.progress.optionalCollected,
                duplicates: total.duplicates + item.progress.duplicates
            )
        }
        let incomplete = summaries
            .filter { $0.progress.requiredTotal > 0 && !$0.progress.isComplete }
            .sorted { $0.progress.fraction > $1.progress.fraction }

        return HomeSummary(
            totalItems: active.reduce(0) { $0 + $1.quantity },
            recordCount: active.count,
            collectionCount: collections.collections(includeArchived: false).count,
            overallSetProgress: overall,
            incompleteSets: Array(incomplete.prefix(3)),
            needsReview: active.filter(\.needsReview).sorted { $0.updatedAt > $1.updatedAt },
            duplicateExtras: DuplicateStats.extraPieces(coins: active, groups: groups),
            duplicateGroupCount: groups.count,
            recentItems: Array(active.sorted { $0.createdAt > $1.createdAt }.prefix(8)),
            wantedCount: wishes.wishes().filter { $0.status == .wanted }.count
        )
    }
}

enum DuplicateStats {
    /// Extra physical pieces: every group counts all but one record, and a
    /// record with quantity N counts N − 1.
    static func extraPieces(coins: [Coin], groups: [DuplicateGroup]) -> Int {
        let activeIDs = Set(coins.map(\.id))
        let grouped = groups.reduce(0) { total, group in
            total + max(0, group.coinIDs.filter { activeIDs.contains($0) }.count - 1)
        }
        let multiples = coins.reduce(0) { $0 + max(0, $1.quantity - 1) }
        return grouped + multiples
    }
}

// MARK: - Reports

enum ReportPeriod: String, CaseIterable, Identifiable {
    case days30
    case days90
    case year
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .days30: return "30 days"
        case .days90: return "90 days"
        case .year: return "12 months"
        case .all: return "All time"
        }
    }

    func startDate(from now: Date, earliest: Date?) -> Date {
        let calendar = Calendar.current
        switch self {
        case .days30: return calendar.date(byAdding: .day, value: -30, to: now) ?? now
        case .days90: return calendar.date(byAdding: .day, value: -90, to: now) ?? now
        case .year: return calendar.date(byAdding: .month, value: -12, to: now) ?? now
        case .all: return earliest.map { min($0, now) } ?? now
        }
    }
}

struct ReportFilter: Hashable {
    var collectionID: UUID?
    var kind: ItemKind?
}

struct GrowthBucket: Identifiable, Hashable {
    var start: Date
    var label: String
    var added: Int
    var cumulative: Int
    var coinIDs: [UUID]
    var id: Date { start }
}

struct CategoryCount: Identifiable, Hashable {
    var name: String
    var count: Int
    var coinIDs: [UUID]
    var id: String { name }
}

struct ValuePoint: Identifiable, Hashable {
    var note: ValueNote
    var coinName: String
    var id: UUID { note.id }
}

struct CollectionReport {
    var period: ReportPeriod
    var filter: ReportFilter
    var sourceCoins: [Coin]
    var addedInPeriod: [Coin]
    var growth: [GrowthBucket]
    var sets: [SetSummary]
    var byCountry: [CategoryCount]
    var byMaterial: [CategoryCount]
    var byKind: [CategoryCount]
    var duplicateGroups: [DuplicateGroup]
    var duplicateExtras: Int
    var valueHistory: [ValuePoint]
    var referenceTotals: [MoneyAmount]

    var totalPieces: Int { sourceCoins.reduce(0) { $0 + $1.quantity } }
    var hasData: Bool { !sourceCoins.isEmpty }
}

struct BuildReportUseCase {
    let coins: CoinRepository
    let sets: SetRepository
    let duplicates: DuplicateRepository
    let valueNotes: ValueNoteRepository
    let clock: Clock

    func execute(period: ReportPeriod, filter: ReportFilter) -> CollectionReport {
        let now = clock.now
        let allCoins = coins.coins(includeArchived: true)
        let source = allCoins.filter { coin in
            !coin.isArchived
                && (filter.collectionID == nil || coin.collectionID == filter.collectionID)
                && (filter.kind == nil || coin.kind == filter.kind)
        }
        let sourceIDs = Set(source.map(\.id))
        let start = period.startDate(from: now, earliest: source.map(\.createdAt).min())
        let added = source.filter { $0.createdAt >= start }.sorted { $0.createdAt < $1.createdAt }

        let groups = duplicates.groups().filter { !Set($0.coinIDs).isDisjoint(with: sourceIDs) }
        let allSets = sets.sets(includeArchived: true)
        let calculator = SetProgressCalculator(coins: allCoins, sets: allSets, groups: duplicates.groups())
        let setRows = sets.sets(includeArchived: false)
            .filter { filter.collectionID == nil || $0.collectionID == filter.collectionID }
            .map { SetSummary(set: $0, progress: calculator.progress(for: $0)) }
            .filter { $0.progress.requiredTotal + $0.progress.optionalTotal > 0 }

        let names = Dictionary(uniqueKeysWithValues: allCoins.map { ($0.id, $0.displayName) })
        let notes = valueNotes.valueNotes(coinID: nil)
            .filter { sourceIDs.contains($0.coinID) && $0.valueDate >= start }
            .sorted { $0.valueDate < $1.valueDate }

        return CollectionReport(
            period: period,
            filter: filter,
            sourceCoins: source,
            addedInPeriod: added,
            growth: Self.growth(for: source, from: start, to: now, period: period),
            sets: setRows,
            byCountry: Self.categories(source) { $0.country.isBlank ? "Not set" : $0.country },
            byMaterial: Self.categories(source) { $0.material.isBlank ? "Not set" : $0.material },
            byKind: Self.categories(source) { $0.kind.pluralTitle },
            duplicateGroups: groups,
            duplicateExtras: DuplicateStats.extraPieces(coins: source, groups: groups),
            valueHistory: notes.map { ValuePoint(note: $0, coinName: names[$0.coinID] ?? "Deleted item") },
            referenceTotals: ValueNoteUseCase.referenceTotals(notes: valueNotes.valueNotes(coinID: nil), coinIDs: sourceIDs)
        )
    }

    static func categories(_ coins: [Coin], key: (Coin) -> String) -> [CategoryCount] {
        var buckets: [String: (display: String, count: Int, ids: [UUID])] = [:]
        for coin in coins {
            let display = key(coin).trimmed
            let normalized = display.normalizedKey
            var bucket = buckets[normalized] ?? (display, 0, [])
            bucket.count += coin.quantity
            bucket.ids.append(coin.id)
            buckets[normalized] = bucket
        }
        return buckets.values
            .map { CategoryCount(name: $0.display, count: $0.count, coinIDs: $0.ids) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }

    static func growth(for coins: [Coin], from start: Date, to end: Date, period: ReportPeriod) -> [GrowthBucket] {
        let calendar = Calendar.current
        let component: Calendar.Component
        let formatter = DateFormatter()
        switch period {
        case .days30, .days90:
            component = .weekOfYear
            formatter.setLocalizedDateFormatFromTemplate("d MMM")
        case .year, .all:
            component = .month
            formatter.setLocalizedDateFormatFromTemplate("MMM")
        }
        guard let firstInterval = calendar.dateInterval(of: component, for: start) else { return [] }
        var bucketStarts: [Date] = []
        var cursor = firstInterval.start
        while cursor <= end && bucketStarts.count < 240 {
            bucketStarts.append(cursor)
            guard let next = calendar.date(byAdding: component == .month ? .month : .weekOfYear, value: 1, to: cursor) else { break }
            cursor = next
        }
        // For "all time" with long histories, keep the chart readable.
        if bucketStarts.count > 24 {
            bucketStarts = Array(bucketStarts.suffix(24))
        }
        var cumulative = coins.filter { $0.createdAt < (bucketStarts.first ?? start) }.reduce(0) { $0 + $1.quantity }
        return bucketStarts.enumerated().map { index, bucketStart in
            let bucketEnd = index + 1 < bucketStarts.count ? bucketStarts[index + 1] : Date.distantFuture
            let inBucket = coins.filter { $0.createdAt >= bucketStart && $0.createdAt < bucketEnd }
            let added = inBucket.reduce(0) { $0 + $1.quantity }
            cumulative += added
            return GrowthBucket(start: bucketStart, label: formatter.string(from: bucketStart), added: added,
                                cumulative: cumulative, coinIDs: inBucket.map(\.id))
        }
    }
}
