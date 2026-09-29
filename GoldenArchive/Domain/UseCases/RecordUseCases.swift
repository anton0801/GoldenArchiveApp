//
//  RecordUseCases.swift
//  GoldenArchive
//
//  Domain layer — condition notes, provenance documents, wishes, goals,
//  value notes and exhibitions.
//

import Foundation

// MARK: - Condition

struct ConditionUseCase {
    let conditions: ConditionRepository
    let media: MediaRepository
    let clock: Clock

    /// Every save of an existing observation adds a dated revision line.
    func save(_ observation: ConditionObservation) {
        let now = clock.now
        var copy = observation
        copy.scratches = copy.scratches.trimmed
        copy.color = copy.color.trimmed
        copy.userGrade = copy.userGrade.trimmed
        copy.note = copy.note.trimmed
        if let existing = conditions.observation(id: observation.id) {
            let changed = Self.changedFields(existing, copy)
            guard !changed.isEmpty else { return }
            copy.revisions.append(ChangeEntry(date: now, summary: "Edited: \(changed.joined(separator: ", "))."))
            let removed = Set(existing.closeUps).subtracting(copy.closeUps)
            media.delete(Array(removed))
        } else {
            copy.revisions = [ChangeEntry(date: now, summary: "Observation recorded.")]
        }
        copy.updatedAt = now
        conditions.save(copy)
    }

    func delete(id: UUID) {
        guard let observation = conditions.observation(id: id) else { return }
        media.delete(observation.closeUps)
        conditions.deleteObservation(id: id)
    }

    static func changedFields(_ a: ConditionObservation, _ b: ConditionObservation) -> [String] {
        var fields: [String] = []
        if !Calendar.current.isDate(a.observedOn, inSameDayAs: b.observedOn) { fields.append("date") }
        if a.side != b.side { fields.append("side") }
        if a.wear != b.wear { fields.append("wear") }
        if a.scratches != b.scratches { fields.append("scratches") }
        if a.color != b.color { fields.append("color") }
        if a.cleaning != b.cleaning { fields.append("cleaning history") }
        if a.userGrade != b.userGrade { fields.append("grade text") }
        if a.closeUps != b.closeUps { fields.append("close-ups") }
        if a.note != b.note { fields.append("note") }
        return fields
    }
}

// MARK: - Provenance

struct DocumentUseCase {
    let documents: DocumentRepository
    let media: MediaRepository
    let clock: Clock

    func save(_ document: ProvenanceDocument) {
        var copy = document
        copy.title = copy.title.trimmed
        copy.sourceNote = copy.sourceNote.trimmed
        copy.privateNote = copy.privateNote.trimmed
        copy.updatedAt = clock.now
        documents.save(copy)
    }

    /// Imports a picked file. The record shows Uploading → Available, or
    /// Failed with the reason; a failed replacement keeps the previous file.
    func attachFile(documentID: UUID, from url: URL, contentType: String, originalName: String?) async {
        let previous = await MainActor.run { () -> StoredFile? in
            guard var document = documents.document(id: documentID) else { return nil }
            let previous = document.file
            document.fileState = .uploading
            document.updatedAt = clock.now
            documents.save(document)
            return previous
        }
        do {
            let stored = try await media.importFile(from: url, contentType: contentType, originalName: originalName)
            await MainActor.run {
                guard var document = documents.document(id: documentID) else {
                    media.delete(stored)
                    return
                }
                document.file = stored
                document.fileState = .available
                document.updatedAt = clock.now
                documents.save(document)
                if let previous, previous != stored { media.delete(previous) }
            }
        } catch {
            await MainActor.run {
                guard var document = documents.document(id: documentID) else { return }
                document.fileState = .failed(reason: error.localizedDescription)
                document.updatedAt = clock.now
                documents.save(document)
            }
        }
    }

    /// Stores in-memory data (a scan or a photo) the same honest way.
    func attachData(documentID: UUID, data: Data, contentType: String, originalName: String?) {
        guard var document = documents.document(id: documentID) else { return }
        let previous = document.file
        do {
            let stored = try media.store(data: data, contentType: contentType, originalName: originalName)
            document.file = stored
            document.fileState = .available
            if let previous { media.delete(previous) }
        } catch {
            document.fileState = .failed(reason: error.localizedDescription)
        }
        document.updatedAt = clock.now
        documents.save(document)
    }

    func link(documentID: UUID, coinIDs: [UUID]) {
        guard var document = documents.document(id: documentID) else { return }
        document.linkedCoinIDs = Array(NSOrderedSet(array: coinIDs)) as? [UUID] ?? coinIDs
        document.updatedAt = clock.now
        documents.save(document)
    }

    func delete(id: UUID) {
        guard let document = documents.document(id: id) else { return }
        if let file = document.file { media.delete(file) }
        documents.deleteDocument(id: id)
    }

    func removeFile(documentID: UUID) {
        guard var document = documents.document(id: documentID) else { return }
        if let file = document.file { media.delete(file) }
        document.file = nil
        document.fileState = .none
        document.updatedAt = clock.now
        documents.save(document)
    }
}

// MARK: - Wish list

struct WishUseCase {
    let wishes: WishRepository
    let clock: Clock

    func save(_ wish: WishItem) {
        var copy = wish
        copy.title = copy.title.trimmed
        copy.targetNote = copy.targetNote.trimmed
        copy.sourceLink = copy.sourceLink.trimmed
        copy.updatedAt = clock.now
        wishes.save(copy)
    }

    func delete(id: UUID) { wishes.deleteWish(id: id) }

    func reopen(id: UUID) {
        guard var wish = wishes.wish(id: id) else { return }
        wish.status = .wanted
        wish.acquiredAt = nil
        wish.acquiredCoinID = nil
        save(wish)
    }
}

// MARK: - Goals

struct GoalProgress: Hashable {
    var current: Int
    var target: Int
    var detail: String

    var fraction: Double { target == 0 ? 0 : min(1, Double(current) / Double(target)) }
    var isComplete: Bool { target > 0 && current >= target }
}

struct GoalUseCase {
    let goals: GoalRepository
    let clock: Clock

    func save(_ goal: CollectionGoal) {
        var copy = goal
        copy.title = copy.title.trimmed
        copy.updatedAt = clock.now
        goals.save(copy)
    }

    func delete(id: UUID) { goals.deleteGoal(id: id) }

    /// Progress is always computed from linked records, never typed in.
    static func progress(for goal: CollectionGoal, sets: [CoinSet], coins: [Coin], groups: [DuplicateGroup]) -> GoalProgress {
        switch goal.target {
        case .completeSets(let setIDs):
            let linked = sets.filter { setIDs.contains($0.id) }
            let calculator = SetProgressCalculator(coins: coins, sets: sets, groups: groups)
            let totals = linked.map { calculator.progress(for: $0) }
            let current = totals.reduce(0) { $0 + $1.requiredCollected }
            let target = totals.reduce(0) { $0 + $1.requiredTotal }
            let detail = linked.isEmpty ? "No sets linked" : "\(current) of \(target) required slots in \(linked.count) set\(linked.count == 1 ? "" : "s")"
            return GoalProgress(current: current, target: target, detail: detail)
        case .itemCount(let collectionID, let target):
            let active = coins.filter { !$0.isArchived && (collectionID == nil || $0.collectionID == collectionID) }
            let current = active.reduce(0) { $0 + $1.quantity }
            return GoalProgress(current: current, target: target, detail: "\(current) of \(target) items")
        }
    }
}

// MARK: - Value notes

enum ValueNoteError: String, Error, Hashable {
    case amount = "Enter an amount greater than zero."
    case currency = "Use a three-letter currency code, for example USD."
    case source = "Every value note needs a source, even if it is “my own estimate”."
    case futureDate = "The value date cannot be in the future."
    case link = "The source link must start with http:// or https://."
}

struct ValueNoteUseCase {
    let valueNotes: ValueNoteRepository
    let clock: Clock

    /// Values are never refreshed automatically: a note needs a source and a date.
    func add(coinID: UUID, kind: ValueNoteKind, amountText: String, currency: String, sourceName: String,
             sourceURL: String, valueDate: Date, note: String) -> Result<ValueNote, ValueNoteError> {
        guard let amount = NumberText.parseDecimal(amountText), amount > 0 else { return .failure(.amount) }
        let code = currency.trimmed.uppercased()
        guard code.count == 3, code.allSatisfy(\.isLetter) else { return .failure(.currency) }
        guard !sourceName.isBlank else { return .failure(.source) }
        let link = sourceURL.trimmed
        if !link.isEmpty {
            guard let url = URL(string: link), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
                return .failure(.link)
            }
        }
        guard valueDate <= clock.now.addingTimeInterval(86_400) else { return .failure(.futureDate) }
        let valueNote = ValueNote(
            id: UUID(),
            coinID: coinID,
            kind: kind,
            amount: MoneyAmount(amount: amount, currency: code),
            sourceName: sourceName.trimmed,
            sourceURL: link,
            valueDate: valueDate,
            note: note.trimmed,
            createdAt: clock.now
        )
        valueNotes.save(valueNote)
        return .success(valueNote)
    }

    func delete(id: UUID) { valueNotes.deleteValueNote(id: id) }

    /// Latest note per record, summed per currency. Always labelled as reference notes.
    static func referenceTotals(notes: [ValueNote], coinIDs: Set<UUID>) -> [MoneyAmount] {
        let latest = Dictionary(grouping: notes.filter { coinIDs.contains($0.coinID) }, by: \.coinID)
            .compactMap { $0.value.max { $0.valueDate < $1.valueDate } }
        let byCurrency = Dictionary(grouping: latest, by: \.amount.currency)
        return byCurrency.map { currency, notes in
            MoneyAmount(amount: notes.reduce(Decimal(0)) { $0 + $1.amount.amount }, currency: currency)
        }.sorted { $0.currency < $1.currency }
    }
}

// MARK: - Exhibition

struct ExhibitionUseCase {
    let exhibitions: ExhibitionRepository
    let clock: Clock

    @discardableResult
    func create(title: String, intro: String, coinIDs: [UUID]) -> Exhibition {
        let now = clock.now
        let exhibition = Exhibition(
            id: UUID(),
            title: title.trimmed,
            intro: intro.trimmed,
            items: coinIDs.map { ExhibitItem(id: UUID(), coinID: $0, caption: "") },
            createdAt: now,
            updatedAt: now
        )
        exhibitions.save(exhibition)
        return exhibition
    }

    func save(_ exhibition: Exhibition) {
        var copy = exhibition
        copy.updatedAt = clock.now
        exhibitions.save(copy)
    }

    func delete(id: UUID) { exhibitions.deleteExhibition(id: id) }
}

/// Renders an exhibition into a local file. Nothing is uploaded.
protocol ExhibitionExporting {
    func exportPDF(_ exhibition: Exhibition, coins: [UUID: Coin], units: MeasurementUnits) throws -> URL
    func exportImage(_ exhibition: Exhibition, coins: [UUID: Coin], units: MeasurementUnits) throws -> URL
}
