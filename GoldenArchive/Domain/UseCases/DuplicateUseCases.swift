//
//  DuplicateUseCases.swift
//  GoldenArchive
//
//  Domain layer — personal duplicate bookkeeping. Merging metadata never
//  touches photos or provenance, and nothing is ever sold or traded here.
//

import Foundation

struct DuplicateFinder {
    /// Active records that share type, country, year, denomination and mint
    /// but are not grouped together yet.
    static func possibleDuplicates(coins: [Coin], groups: [DuplicateGroup]) -> [[Coin]] {
        let groupOf: [UUID: UUID] = Dictionary(
            groups.flatMap { group in group.coinIDs.map { ($0, group.id) } },
            uniquingKeysWith: { first, _ in first }
        )
        let candidates = coins.filter { !$0.isArchived && !$0.country.isBlank && !$0.denomination.isBlank && $0.year != nil }
        let buckets = Dictionary(grouping: candidates) { coin in
            [coin.kind.rawValue, coin.country.normalizedKey, "\(coin.year ?? 0)", coin.denomination.normalizedKey, coin.mint.normalizedKey]
                .joined(separator: "|")
        }
        return buckets.values
            .filter { bucket in
                guard bucket.count > 1 else { return false }
                let groupIDs = Set(bucket.map { groupOf[$0.id] })
                return !(groupIDs.count == 1 && groupIDs.first! != nil)
            }
            .map { $0.sorted { $0.createdAt < $1.createdAt } }
            .sorted { ($0.first?.displayName ?? "") < ($1.first?.displayName ?? "") }
    }

    /// Other records that look like the same issue as `coin`.
    static func suggestions(for coin: Coin, in coins: [Coin]) -> [Coin] {
        coins.filter { other in
            guard other.id != coin.id, !other.isArchived else { return false }
            var score = 0
            if !coin.country.isBlank && other.country.normalizedKey == coin.country.normalizedKey { score += 1 }
            if let year = coin.year, other.year == year { score += 1 }
            if !coin.denomination.isBlank && other.denomination.normalizedKey == coin.denomination.normalizedKey { score += 1 }
            if !coin.name.isBlank && other.name.normalizedKey == coin.name.normalizedKey { score += 1 }
            return score >= 2
        }
    }
}

enum MergeField: String, CaseIterable, Identifiable {
    case kind, country, year, denomination, mint, material, diameter, weight, edge, catalogReference

    var id: String { rawValue }

    var title: String {
        switch self {
        case .kind: return "Type"
        case .country: return "Country"
        case .year: return "Year"
        case .denomination: return "Denomination"
        case .mint: return "Mint"
        case .material: return "Material"
        case .diameter: return "Diameter"
        case .weight: return "Weight"
        case .edge: return "Edge"
        case .catalogReference: return "Catalog reference"
        }
    }
}

struct MergeChange: Identifiable, Hashable {
    var coinID: UUID
    var coinName: String
    var field: MergeField
    var from: String
    var to: String
    var id: String { "\(coinID.uuidString)-\(field.rawValue)" }
}

struct DuplicateUseCase {
    let duplicates: DuplicateRepository
    let coins: CoinRepository
    let clock: Clock

    /// Groups two records. Existing groups are joined or merged.
    @discardableResult
    func markDuplicate(_ coinID: UUID, of otherID: UUID) -> DuplicateGroup? {
        guard coinID != otherID, let coin = coins.coin(id: coinID), coins.coin(id: otherID) != nil else { return nil }
        let now = clock.now
        let groups = duplicates.groups()
        let first = groups.first { $0.coinIDs.contains(coinID) }
        let second = groups.first { $0.coinIDs.contains(otherID) }

        var group: DuplicateGroup
        switch (first, second) {
        case let (a?, b?) where a.id == b.id:
            return a
        case let (a?, b?):
            group = a
            for member in b.members where !group.coinIDs.contains(member.coinID) { group.members.append(member) }
            duplicates.deleteGroup(id: b.id)
        case let (a?, nil):
            group = a
            group.members.append(DuplicateMember(coinID: otherID, status: .undecided))
        case let (nil, b?):
            group = b
            group.members.append(DuplicateMember(coinID: coinID, status: .undecided))
        case (nil, nil):
            group = DuplicateGroup(
                id: UUID(),
                title: coin.displayName,
                members: [DuplicateMember(coinID: otherID, status: .keep), DuplicateMember(coinID: coinID, status: .undecided)],
                note: "",
                reviewedAt: nil,
                createdAt: now,
                updatedAt: now
            )
        }
        group.reviewedAt = nil
        group.updatedAt = now
        duplicates.save(group)
        return group
    }

    @discardableResult
    func createGroup(coinIDs: [UUID]) -> DuplicateGroup? {
        guard coinIDs.count > 1 else { return nil }
        var group: DuplicateGroup?
        for id in coinIDs.dropFirst() {
            group = markDuplicate(id, of: coinIDs[0])
        }
        return group
    }

    func setStatus(groupID: UUID, coinID: UUID, status: KeepStatus) {
        guard var group = duplicates.group(id: groupID), let index = group.members.firstIndex(where: { $0.coinID == coinID }) else { return }
        group.members[index].status = status
        group.updatedAt = clock.now
        duplicates.save(group)
    }

    /// "Keep Both / Keep All": every record stays as an intentional copy.
    func keepAll(groupID: UUID) {
        guard var group = duplicates.group(id: groupID) else { return }
        for index in group.members.indices { group.members[index].status = .keep }
        group.reviewedAt = clock.now
        group.updatedAt = clock.now
        duplicates.save(group)
    }

    func removeFromGroup(groupID: UUID, coinID: UUID) {
        guard var group = duplicates.group(id: groupID) else { return }
        group.members.removeAll { $0.coinID == coinID }
        if group.members.count < 2 {
            duplicates.deleteGroup(id: groupID)
        } else {
            group.updatedAt = clock.now
            duplicates.save(group)
        }
    }

    func dissolve(groupID: UUID) {
        duplicates.deleteGroup(id: groupID)
    }

    func updateNote(groupID: UUID, note: String) {
        guard var group = duplicates.group(id: groupID) else { return }
        group.note = note
        group.updatedAt = clock.now
        duplicates.save(group)
    }

    // MARK: Merge metadata

    func mergePreview(groupID: UUID, primaryID: UUID, fields: Set<MergeField>, overwrite: Bool, units: MeasurementUnits) -> [MergeChange] {
        guard let group = duplicates.group(id: groupID), let primary = coins.coin(id: primaryID) else { return [] }
        return group.coinIDs.filter { $0 != primaryID }.compactMap { coins.coin(id: $0) }.flatMap { target in
            MergeField.allCases.filter { fields.contains($0) }.compactMap { field -> MergeChange? in
                let (from, to, blank) = Self.values(field, target: target, primary: primary, units: units)
                guard from != to, !to.isEmpty, overwrite || blank else { return nil }
                return MergeChange(coinID: target.id, coinName: target.displayName, field: field, from: from.isEmpty ? "—" : from, to: to)
            }
        }
    }

    /// Copies chosen attributes from the primary record. Photos, documents,
    /// condition notes and value notes are never touched.
    @discardableResult
    func applyMerge(groupID: UUID, primaryID: UUID, fields: Set<MergeField>, overwrite: Bool, units: MeasurementUnits) -> Int {
        let changes = mergePreview(groupID: groupID, primaryID: primaryID, fields: fields, overwrite: overwrite, units: units)
        guard let primary = coins.coin(id: primaryID), !changes.isEmpty else { return 0 }
        let now = clock.now
        let byCoin = Dictionary(grouping: changes, by: \.coinID)
        let updated: [Coin] = byCoin.compactMap { coinID, coinChanges in
            guard var coin = coins.coin(id: coinID) else { return nil }
            for change in coinChanges {
                switch change.field {
                case .kind: coin.kind = primary.kind
                case .country: coin.country = primary.country
                case .year: coin.year = primary.year
                case .denomination: coin.denomination = primary.denomination
                case .mint: coin.mint = primary.mint
                case .material: coin.material = primary.material
                case .diameter: coin.diameterMM = primary.diameterMM
                case .weight: coin.weightGrams = primary.weightGrams
                case .edge: coin.edge = primary.edge
                case .catalogReference: coin.catalogReference = primary.catalogReference
                }
            }
            coin.updatedAt = now
            coin.history.append(ChangeEntry(
                date: now,
                summary: "Metadata merged from “\(primary.displayName)”: \(coinChanges.map { $0.field.title.lowercased() }.joined(separator: ", "))."
            ))
            return coin
        }
        coins.save(updated)
        return changes.count
    }

    private static func values(_ field: MergeField, target: Coin, primary: Coin, units: MeasurementUnits) -> (String, String, Bool) {
        switch field {
        case .kind: return (target.kind.title, primary.kind.title, false)
        case .country: return (target.country, primary.country, target.country.isBlank)
        case .year: return (target.year.map(YearText.display) ?? "", primary.year.map(YearText.display) ?? "", target.year == nil)
        case .denomination: return (target.denomination, primary.denomination, target.denomination.isBlank)
        case .mint: return (target.mint, primary.mint, target.mint.isBlank)
        case .material: return (target.material, primary.material, target.material.isBlank)
        case .diameter: return (units.diameterText(target.diameterMM) ?? "", units.diameterText(primary.diameterMM) ?? "", target.diameterMM == nil)
        case .weight: return (units.weightText(target.weightGrams) ?? "", units.weightText(primary.weightGrams) ?? "", target.weightGrams == nil)
        case .edge: return (target.edge, primary.edge, target.edge.isBlank)
        case .catalogReference: return (target.catalogReference?.title ?? "", primary.catalogReference?.title ?? "", target.catalogReference == nil)
        }
    }
}
