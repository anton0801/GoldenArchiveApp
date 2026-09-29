//
//  SetUseCases.swift
//  GoldenArchive
//
//  Domain layer — album / set logic: progress, linking with the quantity
//  rule, templates and wish-list hand-off.
//

import Foundation

// MARK: - Progress

enum SlotState: Hashable {
    case collected
    case missing
    case optionalMissing
}

struct SlotStatus: Identifiable, Hashable {
    var slot: SetSlot
    var state: SlotState
    var coin: Coin?
    /// The linked record has more physical pieces than its slots use, or it
    /// belongs to a duplicate group.
    var isDuplicate: Bool
    var id: UUID { slot.id }
}

struct SetProgress: Hashable {
    var requiredTotal: Int
    var requiredCollected: Int
    var optionalTotal: Int
    var optionalCollected: Int
    var duplicates: Int

    var collected: Int { requiredCollected + optionalCollected }
    var missing: Int { requiredTotal - requiredCollected }
    var fraction: Double { requiredTotal == 0 ? 0 : Double(requiredCollected) / Double(requiredTotal) }
    var isComplete: Bool { requiredTotal > 0 && requiredCollected == requiredTotal }
    var percentText: String { "\(Int((fraction * 100).rounded()))%" }

    static let empty = SetProgress(requiredTotal: 0, requiredCollected: 0, optionalTotal: 0, optionalCollected: 0, duplicates: 0)
}

/// Pure calculator over already-loaded records.
struct SetProgressCalculator {
    let coinsByID: [UUID: Coin]
    let slotUsage: [UUID: Int]
    let groupedCoinIDs: Set<UUID>

    init(coins: [Coin], sets: [CoinSet], groups: [DuplicateGroup]) {
        coinsByID = Dictionary(uniqueKeysWithValues: coins.map { ($0.id, $0) })
        slotUsage = SetProgressCalculator.usage(in: sets)
        groupedCoinIDs = Set(groups.flatMap(\.coinIDs))
    }

    static func usage(in sets: [CoinSet]) -> [UUID: Int] {
        var usage: [UUID: Int] = [:]
        for set in sets {
            for slot in set.slots {
                if let coinID = slot.linkedCoinID { usage[coinID, default: 0] += max(1, slot.quantityNeeded) }
            }
        }
        return usage
    }

    func statuses(for set: CoinSet) -> [SlotStatus] {
        set.slots.map { slot in
            let coin = slot.linkedCoinID.flatMap { coinsByID[$0] }
            let state: SlotState = coin != nil ? .collected : (slot.isOptional ? .optionalMissing : .missing)
            var isDuplicate = false
            if let coin {
                isDuplicate = coin.quantity > (slotUsage[coin.id] ?? 0) || groupedCoinIDs.contains(coin.id)
            }
            return SlotStatus(slot: slot, state: state, coin: coin, isDuplicate: isDuplicate)
        }
    }

    func progress(for set: CoinSet) -> SetProgress {
        let statuses = statuses(for: set)
        let required = statuses.filter { !$0.slot.isOptional }
        let optional = statuses.filter { $0.slot.isOptional }
        return SetProgress(
            requiredTotal: required.count,
            requiredCollected: required.filter { $0.state == .collected }.count,
            optionalTotal: optional.count,
            optionalCollected: optional.filter { $0.state == .collected }.count,
            duplicates: statuses.filter(\.isDuplicate).count
        )
    }
}

// MARK: - Matching

struct SlotMatcher {
    /// How many of the slot's expectations a record meets, and how many were set.
    static func match(_ coin: Coin, _ expected: ExpectedAttributes) -> (matched: Int, total: Int) {
        var matched = 0
        var total = 0
        func compare(_ expected: String, _ actual: String) {
            guard !expected.isBlank else { return }
            total += 1
            let e = expected.normalizedKey, a = actual.normalizedKey
            if !a.isEmpty && (a == e || a.contains(e) || e.contains(a)) { matched += 1 }
        }
        compare(expected.country, coin.country)
        if let year = expected.year {
            total += 1
            if coin.year == year { matched += 1 }
        }
        compare(expected.denomination, coin.denomination)
        compare(expected.mint, coin.mint)
        compare(expected.material, coin.material)
        return (matched, total)
    }
}

// MARK: - Linking

enum SlotLinkResult: Hashable {
    case linked
    case alreadyLinked
    /// One record cannot fill more unique slots than its quantity without
    /// the user confirming how many pieces they really own.
    case needsQuantityConfirmation(currentQuantity: Int, requiredQuantity: Int, otherSlots: [String])
    case notFound
}

struct LinkCoinToSlotUseCase {
    let coins: CoinRepository
    let sets: SetRepository
    let clock: Clock

    func execute(coinID: UUID, slot reference: SlotReference, confirmQuantity: Bool) -> SlotLinkResult {
        guard var coin = coins.coin(id: coinID),
              var set = sets.set(id: reference.setID),
              let index = set.slots.firstIndex(where: { $0.id == reference.slotID })
        else { return .notFound }

        if set.slots[index].linkedCoinID == coinID { return .alreadyLinked }

        let allSets = sets.sets(includeArchived: true)
        var otherSlotTitles: [String] = []
        var usedElsewhere = 0
        for other in allSets {
            for slot in other.slots where slot.linkedCoinID == coinID && slot.id != reference.slotID {
                usedElsewhere += max(1, slot.quantityNeeded)
                otherSlotTitles.append("\(other.name) — \(slot.displayTitle)")
            }
        }
        let required = usedElsewhere + max(1, set.slots[index].quantityNeeded)

        if required > coin.quantity {
            guard confirmQuantity else {
                return .needsQuantityConfirmation(currentQuantity: coin.quantity, requiredQuantity: required, otherSlots: otherSlotTitles)
            }
            let now = clock.now
            coin.history.append(ChangeEntry(date: now, summary: "Quantity confirmed as \(required) to fill set slots."))
            coin.quantity = required
            coin.updatedAt = now
            coins.save(coin)
        }

        let now = clock.now
        set.slots[index].linkedCoinID = coinID
        set.slots[index].linkedAt = now
        set.updatedAt = now
        sets.save(set)
        return .linked
    }

    func unlink(_ reference: SlotReference) {
        guard var set = sets.set(id: reference.setID),
              let index = set.slots.firstIndex(where: { $0.id == reference.slotID })
        else { return }
        set.slots[index].linkedCoinID = nil
        set.slots[index].linkedAt = nil
        set.updatedAt = clock.now
        sets.save(set)
    }

    /// Every slot that currently holds the record.
    func slots(for coinID: UUID) -> [(set: CoinSet, slot: SetSlot)] {
        sets.sets(includeArchived: true).flatMap { set in
            set.slots.filter { $0.linkedCoinID == coinID }.map { (set, $0) }
        }
    }
}

// MARK: - Editing sets

struct SetEditingUseCase {
    let sets: SetRepository
    let wishes: WishRepository
    let clock: Clock

    @discardableResult
    func createSet(name: String, collectionID: UUID?, note: String, slots: [SetSlot], templateName: String?) -> CoinSet {
        let now = clock.now
        let set = CoinSet(name: name.trimmed, collectionID: collectionID, note: note.trimmed, slots: slots,
                          templateName: templateName, createdAt: now, updatedAt: now)
        sets.save(set)
        return set
    }

    func update(_ set: CoinSet) {
        var copy = set
        copy.updatedAt = clock.now
        sets.save(copy)
    }

    func addSlot(setID: UUID, slot: SetSlot) {
        guard var set = sets.set(id: setID) else { return }
        set.slots.append(slot)
        update(set)
    }

    func updateSlot(setID: UUID, slot: SetSlot) {
        guard var set = sets.set(id: setID), let index = set.slots.firstIndex(where: { $0.id == slot.id }) else { return }
        set.slots[index] = slot
        update(set)
    }

    func removeSlot(setID: UUID, slotID: UUID) {
        guard var set = sets.set(id: setID) else { return }
        set.slots.removeAll { $0.id == slotID }
        update(set)
        let now = clock.now
        let affected: [WishItem] = wishes.wishes().compactMap { wish in
            guard wish.linkedSlot?.slotID == slotID else { return nil }
            var copy = wish
            copy.linkedSlot = nil
            copy.updatedAt = now
            return copy
        }
        if !affected.isEmpty { wishes.save(affected) }
    }

    func moveSlots(setID: UUID, from source: IndexSet, to destination: Int) {
        guard var set = sets.set(id: setID) else { return }
        set.slots.move(fromOffsets: source, toOffset: destination)
        update(set)
    }

    func toggleOptional(setID: UUID, slotID: UUID) {
        guard var set = sets.set(id: setID), let index = set.slots.firstIndex(where: { $0.id == slotID }) else { return }
        set.slots[index].isOptional.toggle()
        update(set)
    }

    func archive(setID: UUID, archived: Bool) {
        guard var set = sets.set(id: setID) else { return }
        set.archivedAt = archived ? clock.now : nil
        update(set)
    }

    func delete(setID: UUID) {
        let now = clock.now
        let affected: [WishItem] = wishes.wishes().compactMap { wish in
            guard wish.linkedSlot?.setID == setID else { return nil }
            var copy = wish
            copy.linkedSlot = nil
            copy.updatedAt = now
            return copy
        }
        if !affected.isEmpty { wishes.save(affected) }
        sets.deleteSet(id: setID)
    }

    /// Creates wishes for required, empty slots that no open wish covers yet.
    @discardableResult
    func addMissingToWishList(setID: UUID) -> Int {
        guard let set = sets.set(id: setID) else { return 0 }
        let covered = Set(wishes.wishes().filter { $0.status == .wanted }.compactMap { $0.linkedSlot?.slotID })
        let now = clock.now
        let newWishes: [WishItem] = set.slots.compactMap { slot in
            guard slot.linkedCoinID == nil, !slot.isOptional, !covered.contains(slot.id) else { return nil }
            return WishItem(
                title: slot.displayTitle,
                expected: slot.expected,
                priority: .medium,
                linkedSlot: SlotReference(setID: set.id, slotID: slot.id),
                note: "From set “\(set.name)”.",
                createdAt: now,
                updatedAt: now
            )
        }
        if !newWishes.isEmpty { wishes.save(newWishes) }
        return newWishes.count
    }

    @discardableResult
    func saveAsTemplate(setID: UUID, name: String) -> SetTemplate? {
        guard let set = sets.set(id: setID) else { return nil }
        let template = SetTemplate(
            id: UUID(),
            name: name.trimmed.isEmpty ? set.name : name.trimmed,
            summary: "\(set.slots.count) slots saved from “\(set.name)”",
            slots: set.slots.map { TemplateSlot(title: $0.title, expected: $0.expected, isOptional: $0.isOptional, quantityNeeded: $0.quantityNeeded) },
            isBuiltIn: false,
            createdAt: clock.now
        )
        sets.save(template)
        return template
    }

    /// Builds slots from a template; blank country/year expectations can be filled for every slot.
    static func slots(from template: SetTemplate, country: String, year: Int?) -> [SetSlot] {
        template.slots.map { item in
            var expected = item.expected
            if expected.country.isBlank && !country.isBlank { expected.country = country.trimmed }
            if expected.year == nil, let year { expected.year = year }
            return SetSlot(title: item.title, expected: expected, isOptional: item.isOptional, quantityNeeded: item.quantityNeeded)
        }
    }
}

// MARK: - Built-in templates

enum BuiltInTemplates {
    static let all: [SetTemplate] = [euroCirculation, usCirculation, ukCirculation, usStateQuarters]

    private static let referenceDate = Date(timeIntervalSince1970: 0)

    static let euroCirculation = SetTemplate(
        id: UUID(uuidString: "6B0F7F7E-1A51-4C7B-9D0B-5D1B8E0A0001")!,
        name: "Euro circulation set",
        summary: "8 denominations from 1 cent to 2 euro. Add the country and year you collect.",
        slots: [
            ("1 cent", "Copper-covered steel"), ("2 cent", "Copper-covered steel"), ("5 cent", "Copper-covered steel"),
            ("10 cent", "Nordic gold"), ("20 cent", "Nordic gold"), ("50 cent", "Nordic gold"),
            ("1 euro", "Bimetallic"), ("2 euro", "Bimetallic")
        ].map { TemplateSlot(title: $0.0, expected: ExpectedAttributes(denomination: $0.0, material: $0.1), isOptional: false, quantityNeeded: 1) },
        isBuiltIn: true,
        createdAt: referenceDate
    )

    static let usCirculation = SetTemplate(
        id: UUID(uuidString: "6B0F7F7E-1A51-4C7B-9D0B-5D1B8E0A0002")!,
        name: "US circulating coins",
        summary: "Cent to dollar. The half dollar and dollar are optional.",
        slots: [
            ("1 cent", false), ("5 cents", false), ("10 cents", false), ("25 cents", false),
            ("50 cents", true), ("1 dollar", true)
        ].map { TemplateSlot(title: $0.0, expected: ExpectedAttributes(country: "United States", denomination: $0.0), isOptional: $0.1, quantityNeeded: 1) },
        isBuiltIn: true,
        createdAt: referenceDate
    )

    static let ukCirculation = SetTemplate(
        id: UUID(uuidString: "6B0F7F7E-1A51-4C7B-9D0B-5D1B8E0A0003")!,
        name: "UK circulating coins",
        summary: "1 penny to 2 pounds, one slot per denomination.",
        slots: ["1 penny", "2 pence", "5 pence", "10 pence", "20 pence", "50 pence", "1 pound", "2 pounds"]
            .map { TemplateSlot(title: $0, expected: ExpectedAttributes(country: "United Kingdom", denomination: $0), isOptional: false, quantityNeeded: 1) },
        isBuiltIn: true,
        createdAt: referenceDate
    )

    static let usStateQuarters: SetTemplate = {
        let schedule: [(Int, [String])] = [
            (1999, ["Delaware", "Pennsylvania", "New Jersey", "Georgia", "Connecticut"]),
            (2000, ["Massachusetts", "Maryland", "South Carolina", "New Hampshire", "Virginia"]),
            (2001, ["New York", "North Carolina", "Rhode Island", "Vermont", "Kentucky"]),
            (2002, ["Tennessee", "Ohio", "Louisiana", "Indiana", "Mississippi"]),
            (2003, ["Illinois", "Alabama", "Maine", "Missouri", "Arkansas"]),
            (2004, ["Michigan", "Florida", "Texas", "Iowa", "Wisconsin"]),
            (2005, ["California", "Minnesota", "Oregon", "Kansas", "West Virginia"]),
            (2006, ["Nevada", "Nebraska", "Colorado", "North Dakota", "South Dakota"]),
            (2007, ["Montana", "Washington", "Idaho", "Wyoming", "Utah"]),
            (2008, ["Oklahoma", "New Mexico", "Arizona", "Alaska", "Hawaii"])
        ]
        let slots = schedule.flatMap { year, states in
            states.map { state in
                TemplateSlot(
                    title: "\(state) (\(year))",
                    expected: ExpectedAttributes(country: "United States", year: year, denomination: "25 cents"),
                    isOptional: false,
                    quantityNeeded: 1
                )
            }
        }
        return SetTemplate(
            id: UUID(uuidString: "6B0F7F7E-1A51-4C7B-9D0B-5D1B8E0A0004")!,
            name: "US 50 State Quarters (1999–2008)",
            summary: "50 slots in release order, five designs per year.",
            slots: slots,
            isBuiltIn: true,
            createdAt: referenceDate
        )
    }()
}
