//
//  CoinUseCases.swift
//  GoldenArchive
//
//  Domain layer — creating, editing, archiving, moving and deleting items.
//

import Foundation

// MARK: - Form & validation

/// Raw user input from the item editor. Numbers stay text until validated.
struct CoinForm: Hashable {
    var kind: ItemKind = .coin
    var name = ""
    var country = ""
    var yearText = ""
    var isBC = false
    var denomination = ""
    var mint = ""
    var material = ""
    var diameterText = ""
    var weightText = ""
    var edge = ""
    var quantity = 1
    var collectionID: UUID?
    var condition = ""
    var notes = ""
    var tags: [String] = []
    var needsReview = false
    var reviewReason = ""

    init() {}

    init(coin: Coin, units: MeasurementUnits) {
        kind = coin.kind
        name = coin.name
        country = coin.country
        if let year = coin.year {
            yearText = "\(abs(year))"
            isBC = year < 0
        }
        denomination = coin.denomination
        mint = coin.mint
        material = coin.material
        diameterText = coin.diameterMM.map { NumberText.format(units.diameterFromMM($0)) } ?? ""
        weightText = coin.weightGrams.map { NumberText.format(units.weightFromGrams($0)) } ?? ""
        edge = coin.edge
        quantity = coin.quantity
        collectionID = coin.collectionID
        condition = coin.condition
        notes = coin.notes
        tags = coin.tags
        needsReview = coin.needsReview
        reviewReason = coin.reviewReason
    }

    /// Fills blank fields from a reference suggestion. Filled fields stay the user's.
    mutating func applyBlanks(from candidate: CatalogCandidate, units: MeasurementUnits) {
        if name.isBlank { name = candidate.title }
        if country.isBlank { country = candidate.country }
        if yearText.isBlank, let min = candidate.minYear, candidate.maxYear == nil || candidate.maxYear == min {
            yearText = "\(abs(min))"
            isBC = min < 0
        }
        if denomination.isBlank { denomination = candidate.denomination }
        if mint.isBlank, candidate.mints.count == 1 { mint = candidate.mints[0] }
        if material.isBlank { material = candidate.material }
        if diameterText.isBlank, let d = candidate.diameterMM { diameterText = NumberText.format(units.diameterFromMM(d)) }
        if weightText.isBlank, let w = candidate.weightGrams { weightText = NumberText.format(units.weightFromGrams(w)) }
        if edge.isBlank { edge = candidate.edge }
    }
}

enum CoinField: String, CaseIterable {
    case name, year, diameter, weight, quantity
}

struct FieldError: Hashable, Identifiable {
    var field: CoinField
    var message: String
    var id: String { field.rawValue }
}

struct ValidationFailure: Error, Hashable {
    var errors: [FieldError]
}

struct ParsedCoinValues: Hashable {
    var year: Int?
    var diameterMM: Double?
    var weightGrams: Double?
}

enum NumberText {
    /// Accepts "12.5" and "12,5".
    static func parse(_ text: String) -> Double? {
        let cleaned = text.trimmed.replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }

    static func format(_ value: Double, maxFractionDigits: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maxFractionDigits
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func parseDecimal(_ text: String) -> Decimal? {
        let cleaned = text.trimmed.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty else { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }
}

extension MeasurementUnits {
    static let mmPerInch = 25.4
    static let gramsPerTroyOunce = 31.1034768

    var diameterUnit: String { self == .metric ? "mm" : "in" }
    var weightUnit: String { self == .metric ? "g" : "oz t" }

    func diameterFromMM(_ mm: Double) -> Double { self == .metric ? mm : mm / Self.mmPerInch }
    func diameterToMM(_ value: Double) -> Double { self == .metric ? value : value * Self.mmPerInch }
    func weightFromGrams(_ g: Double) -> Double { self == .metric ? g : g / Self.gramsPerTroyOunce }
    func weightToGrams(_ value: Double) -> Double { self == .metric ? value : value * Self.gramsPerTroyOunce }

    func diameterText(_ mm: Double?) -> String? {
        guard let mm else { return nil }
        return "\(NumberText.format(diameterFromMM(mm), maxFractionDigits: self == .metric ? 2 : 3)) \(diameterUnit)"
    }

    func weightText(_ grams: Double?) -> String? {
        guard let grams else { return nil }
        return "\(NumberText.format(weightFromGrams(grams), maxFractionDigits: self == .metric ? 2 : 4)) \(weightUnit)"
    }
}

struct CoinFormValidator {
    let clock: Clock

    func validate(_ form: CoinForm, units: MeasurementUnits) -> Result<ParsedCoinValues, ValidationFailure> {
        var errors: [FieldError] = []
        var parsed = ParsedCoinValues()

        let name = form.name.trimmed
        if name.isEmpty {
            errors.append(FieldError(field: .name, message: "Name is required."))
        } else if name.count > 120 {
            errors.append(FieldError(field: .name, message: "Keep the name under 120 characters."))
        }

        let yearText = form.yearText.trimmed
        if !yearText.isEmpty {
            let currentYear = Calendar(identifier: .gregorian).component(.year, from: clock.now)
            if let value = Int(yearText) {
                if form.isBC {
                    if (1...3000).contains(value) { parsed.year = -value }
                    else { errors.append(FieldError(field: .year, message: "BC years go from 1 to 3000.")) }
                } else if (1...(currentYear + 1)).contains(value) {
                    parsed.year = value
                } else {
                    errors.append(FieldError(field: .year, message: "Enter a year between 1 and \(currentYear + 1)."))
                }
            } else {
                errors.append(FieldError(field: .year, message: "Year must be a whole number."))
            }
        }

        if !form.diameterText.isBlank {
            if let value = NumberText.parse(form.diameterText), value > 0 {
                let mm = units.diameterToMM(value)
                if (0.5...200).contains(mm) { parsed.diameterMM = mm }
                else { errors.append(FieldError(field: .diameter, message: "Diameter should be between 0.5 and 200 mm.")) }
            } else {
                errors.append(FieldError(field: .diameter, message: "Diameter must be a positive number."))
            }
        }

        if !form.weightText.isBlank {
            if let value = NumberText.parse(form.weightText), value > 0 {
                let grams = units.weightToGrams(value)
                if (0.01...5000).contains(grams) { parsed.weightGrams = grams }
                else { errors.append(FieldError(field: .weight, message: "Weight should be between 0.01 g and 5 kg.")) }
            } else {
                errors.append(FieldError(field: .weight, message: "Weight must be a positive number."))
            }
        }

        if !(1...9999).contains(form.quantity) {
            errors.append(FieldError(field: .quantity, message: "Quantity must be between 1 and 9999."))
        }

        return errors.isEmpty ? .success(parsed) : .failure(ValidationFailure(errors: errors))
    }
}

// MARK: - Save

struct SaveCoinRequest {
    /// Stable draft id: saving twice updates the same record.
    var coinID: UUID
    var form: CoinForm
    var photos: [CoinPhoto]
    var catalogReference: CatalogReference?
    var pendingSlot: SlotReference?
    var fulfilledWishID: UUID?
}

struct SaveCoinOutcome {
    var coin: Coin
    var created: Bool
    var slotResult: SlotLinkResult?
}

struct SaveCoinUseCase {
    let coins: CoinRepository
    let settings: SettingsRepository
    let wishes: WishRepository
    let linkSlot: LinkCoinToSlotUseCase
    let validator: CoinFormValidator
    let clock: Clock

    func execute(_ request: SaveCoinRequest) -> Result<SaveCoinOutcome, ValidationFailure> {
        let units = settings.settings().units
        let parsed: ParsedCoinValues
        switch validator.validate(request.form, units: units) {
        case .failure(let failure): return .failure(failure)
        case .success(let values): parsed = values
        }

        let now = clock.now
        let existing = coins.coin(id: request.coinID)
        var coin = existing ?? Coin(id: request.coinID, createdAt: now, updatedAt: now)
        let before = coin
        let form = request.form

        coin.kind = form.kind
        coin.name = form.name.trimmed
        coin.country = form.country.trimmed
        coin.year = parsed.year
        coin.denomination = form.denomination.trimmed
        coin.mint = form.mint.trimmed
        coin.material = form.material.trimmed
        coin.diameterMM = parsed.diameterMM
        coin.weightGrams = parsed.weightGrams
        coin.edge = form.edge.trimmed
        coin.quantity = form.quantity
        coin.collectionID = form.collectionID
        coin.condition = form.condition.trimmed
        coin.notes = form.notes.trimmed
        coin.tags = form.tags.cleanedTags()
        coin.photos = request.photos
        if let reference = request.catalogReference { coin.catalogReference = reference }
        coin.needsReview = form.needsReview
        coin.reviewReason = form.needsReview ? form.reviewReason.trimmed : ""

        if existing == nil {
            let autoReasons = Self.autoReviewReasons(for: coin)
            if !autoReasons.isEmpty {
                coin.needsReview = true
                coin.reviewReason = ([coin.reviewReason] + autoReasons).filter { !$0.isBlank }.joined(separator: " ")
            }
            coin.history.append(ChangeEntry(date: now, summary: request.catalogReference == nil
                ? "Added to the archive."
                : "Added after reviewing a \(request.catalogReference!.sourceName) reference."))
        } else {
            let changed = Self.changedFields(from: before, to: coin)
            guard !changed.isEmpty else {
                return .success(SaveCoinOutcome(coin: before, created: false, slotResult: nil))
            }
            coin.history.append(ChangeEntry(date: now, summary: "Edited: \(changed.joined(separator: ", "))."))
        }
        coin.updatedAt = now
        coins.save(coin)

        var slotResult: SlotLinkResult?
        var wishSlot: SlotReference?
        if let wishID = request.fulfilledWishID, var wish = wishes.wish(id: wishID) {
            wish.status = .acquired
            wish.acquiredCoinID = coin.id
            wish.acquiredAt = now
            wish.updatedAt = now
            wishes.save(wish)
            wishSlot = wish.linkedSlot
        }
        if let slot = request.pendingSlot ?? wishSlot {
            slotResult = linkSlot.execute(coinID: coin.id, slot: slot, confirmQuantity: false)
        }
        return .success(SaveCoinOutcome(coin: coins.coin(id: coin.id) ?? coin, created: existing == nil, slotResult: slotResult))
    }

    static func autoReviewReasons(for coin: Coin) -> [String] {
        var reasons: [String] = []
        let missing = [
            coin.country.isBlank ? "country" : nil,
            coin.year == nil ? "year" : nil,
            coin.denomination.isBlank && coin.kind == .coin ? "denomination" : nil
        ].compactMap { $0 }
        if !missing.isEmpty { reasons.append("Missing \(missing.joined(separator: ", ")).") }
        if coin.photos.contains(where: { $0.quality?.hasGlare == true }) {
            reasons.append("A photo has glare.")
        }
        return reasons
    }

    static func changedFields(from old: Coin, to new: Coin) -> [String] {
        var fields: [String] = []
        if old.kind != new.kind { fields.append("type") }
        if old.name != new.name { fields.append("name") }
        if old.country != new.country { fields.append("country") }
        if old.year != new.year { fields.append("year") }
        if old.denomination != new.denomination { fields.append("denomination") }
        if old.mint != new.mint { fields.append("mint") }
        if old.material != new.material { fields.append("material") }
        if old.diameterMM != new.diameterMM { fields.append("diameter") }
        if old.weightGrams != new.weightGrams { fields.append("weight") }
        if old.edge != new.edge { fields.append("edge") }
        if old.quantity != new.quantity { fields.append("quantity") }
        if old.collectionID != new.collectionID { fields.append("collection") }
        if old.condition != new.condition { fields.append("condition") }
        if old.notes != new.notes { fields.append("notes") }
        if old.tags != new.tags { fields.append("tags") }
        if old.photos != new.photos { fields.append("photos") }
        if old.catalogReference != new.catalogReference { fields.append("catalog reference") }
        if old.needsReview != new.needsReview { fields.append(new.needsReview ? "marked for review" : "review cleared") }
        return fields
    }
}

// MARK: - Review, archive & move

struct UpdateCoinStateUseCase {
    let coins: CoinRepository
    let clock: Clock

    func markReviewed(coinID: UUID) {
        mutate(coinID, summary: "Marked as reviewed.") {
            $0.needsReview = false
            $0.reviewReason = ""
        }
    }

    func markForReview(coinID: UUID, reason: String) {
        mutate(coinID, summary: "Marked for review.") {
            $0.needsReview = true
            $0.reviewReason = reason.trimmed
        }
    }

    func archive(coinID: UUID) {
        mutate(coinID, summary: "Archived.") { $0.archivedAt = clock.now }
    }

    func restore(coinID: UUID) {
        mutate(coinID, summary: "Restored from archive.") { $0.archivedAt = nil }
    }

    func move(coinIDs: [UUID], to collectionID: UUID?, collectionName: String) {
        let now = clock.now
        let updated: [Coin] = coinIDs.compactMap { id in
            guard var coin = coins.coin(id: id), coin.collectionID != collectionID else { return nil }
            coin.collectionID = collectionID
            coin.updatedAt = now
            coin.history.append(ChangeEntry(date: now, summary: "Moved to \(collectionName)."))
            return coin
        }
        if !updated.isEmpty { coins.save(updated) }
    }

    func setQuantity(coinID: UUID, quantity: Int) {
        let clamped = max(1, min(9999, quantity))
        mutate(coinID, summary: "Quantity set to \(clamped).") { $0.quantity = clamped }
    }

    func updatePhotos(coinID: UUID, photos: [CoinPhoto]) {
        mutate(coinID, summary: "Photos updated.") { $0.photos = photos }
    }

    private func mutate(_ id: UUID, summary: String, _ change: (inout Coin) -> Void) {
        guard var coin = coins.coin(id: id) else { return }
        change(&coin)
        coin.updatedAt = clock.now
        coin.history.append(ChangeEntry(date: clock.now, summary: summary))
        coins.save(coin)
    }
}

// MARK: - Delete

struct CoinDeletionImpact {
    struct SlotLine: Hashable {
        var setName: String
        var slotTitle: String
    }

    var coin: Coin
    var slots: [SlotLine]
    var sharedDocuments: [ProvenanceDocument]
    var exclusiveDocuments: [ProvenanceDocument]
    var observationCount: Int
    var closeUpFileCount: Int
    var valueNoteCount: Int
    var photoFileCount: Int
    var duplicateGroupCount: Int
    var exhibitionCount: Int

    var documentCount: Int { sharedDocuments.count + exclusiveDocuments.count }
}

struct DeleteCoinUseCase {
    let coins: CoinRepository
    let collections: CollectionRepository
    let sets: SetRepository
    let documents: DocumentRepository
    let conditions: ConditionRepository
    let duplicates: DuplicateRepository
    let valueNotes: ValueNoteRepository
    let exhibitions: ExhibitionRepository
    let wishes: WishRepository
    let media: MediaRepository
    let clock: Clock

    func impact(coinID: UUID) -> CoinDeletionImpact? {
        guard let coin = coins.coin(id: coinID) else { return nil }
        let slotLines = sets.sets(includeArchived: true).flatMap { set in
            set.slots.filter { $0.linkedCoinID == coinID }
                .map { CoinDeletionImpact.SlotLine(setName: set.name, slotTitle: $0.displayTitle) }
        }
        let linkedDocs = documents.documents().filter { $0.linkedCoinIDs.contains(coinID) }
        let observations = conditions.observations(coinID: coinID)
        return CoinDeletionImpact(
            coin: coin,
            slots: slotLines,
            sharedDocuments: linkedDocs.filter { $0.linkedCoinIDs.count > 1 },
            exclusiveDocuments: linkedDocs.filter { $0.linkedCoinIDs.count == 1 },
            observationCount: observations.count,
            closeUpFileCount: observations.reduce(0) { $0 + $1.closeUps.count },
            valueNoteCount: valueNotes.valueNotes(coinID: coinID).count,
            photoFileCount: coin.allFiles.count,
            duplicateGroupCount: duplicates.groups().filter { $0.coinIDs.contains(coinID) }.count,
            exhibitionCount: exhibitions.exhibitions().filter { $0.items.contains { $0.coinID == coinID } }.count
        )
    }

    /// Documents are only deleted when the user explicitly asks for it;
    /// otherwise they stay in Provenance, unlinked.
    func execute(coinID: UUID, alsoDeleteExclusiveDocuments: Bool) {
        guard let coin = coins.coin(id: coinID) else { return }
        let now = clock.now

        let updatedSets: [CoinSet] = sets.sets(includeArchived: true).compactMap { set in
            guard set.slots.contains(where: { $0.linkedCoinID == coinID }) else { return nil }
            var copy = set
            for index in copy.slots.indices where copy.slots[index].linkedCoinID == coinID {
                copy.slots[index].linkedCoinID = nil
                copy.slots[index].linkedAt = nil
            }
            copy.updatedAt = now
            return copy
        }
        if !updatedSets.isEmpty { sets.save(updatedSets) }

        var docsToSave: [ProvenanceDocument] = []
        for doc in documents.documents() where doc.linkedCoinIDs.contains(coinID) {
            if doc.linkedCoinIDs.count == 1 && alsoDeleteExclusiveDocuments {
                if let file = doc.file { media.delete(file) }
                documents.deleteDocument(id: doc.id)
            } else {
                var copy = doc
                copy.linkedCoinIDs.removeAll { $0 == coinID }
                copy.updatedAt = now
                docsToSave.append(copy)
            }
        }
        if !docsToSave.isEmpty { documents.save(docsToSave) }

        for observation in conditions.observations(coinID: coinID) {
            media.delete(observation.closeUps)
            conditions.deleteObservation(id: observation.id)
        }
        for note in valueNotes.valueNotes(coinID: coinID) {
            valueNotes.deleteValueNote(id: note.id)
        }
        for group in duplicates.groups() where group.coinIDs.contains(coinID) {
            var copy = group
            copy.members.removeAll { $0.coinID == coinID }
            if copy.members.count < 2 {
                duplicates.deleteGroup(id: group.id)
            } else {
                copy.updatedAt = now
                duplicates.save(copy)
            }
        }
        for exhibition in exhibitions.exhibitions() where exhibition.items.contains(where: { $0.coinID == coinID }) {
            var copy = exhibition
            copy.items.removeAll { $0.coinID == coinID }
            copy.updatedAt = now
            exhibitions.save(copy)
        }
        let updatedCollections: [CoinCollection] = collections.collections(includeArchived: true).compactMap { collection in
            guard collection.cover?.coinID == coinID else { return nil }
            var copy = collection
            copy.cover = nil
            copy.updatedAt = now
            return copy
        }
        if !updatedCollections.isEmpty { collections.save(updatedCollections) }
        let updatedWishes: [WishItem] = wishes.wishes().compactMap { wish in
            guard wish.acquiredCoinID == coinID else { return nil }
            var copy = wish
            copy.acquiredCoinID = nil
            copy.updatedAt = now
            return copy
        }
        if !updatedWishes.isEmpty { wishes.save(updatedWishes) }

        media.delete(coin.allFiles)
        coins.deleteCoin(id: coinID)
    }
}

// MARK: - Photos

struct PhotoFilesUseCase {
    let media: MediaRepository

    /// Removes files of photos that were captured in a draft that the user cancelled.
    func discard(_ photos: [CoinPhoto]) {
        media.delete(photos.flatMap(\.allFiles))
    }
}

enum PhotoIntakeError: LocalizedError {
    case originalMissing
    case cropFailed

    var errorDescription: String? {
        switch self {
        case .originalMissing: return "The original photo file is missing."
        case .cropFailed: return "The crop could not be created. Try a larger area."
        }
    }
}

/// Stores a new photo exactly as captured and records measured quality.
struct PhotoIntakeUseCase {
    let media: MediaRepository
    let processor: PhotoProcessing
    let clock: Clock

    func intake(data: Data, contentType: String, side: PhotoSide) throws -> CoinPhoto {
        let original = try media.store(data: data, contentType: contentType, originalName: nil)
        return CoinPhoto(side: side, original: original, capturedAt: clock.now, quality: processor.analyze(data))
    }

    /// Writes a new crop file from the untouched original; the previous crop file is replaced.
    func applyCrop(to photo: CoinPhoto, quarterTurns: Int, region: CropRegion) throws -> CoinPhoto {
        guard let data = media.data(for: photo.original) else { throw PhotoIntakeError.originalMissing }
        var updated = photo
        let isIdentity = region == .full && quarterTurns % 4 == 0
        if isIdentity {
            if let old = photo.cropped { media.delete(old) }
            updated.cropped = nil
            updated.crop = nil
            updated.quarterTurns = 0
            return updated
        }
        guard let rendered = processor.crop(data, quarterTurns: quarterTurns, region: region) else { throw PhotoIntakeError.cropFailed }
        let stored = try media.store(data: rendered, contentType: "image/jpeg", originalName: nil)
        if let old = photo.cropped { media.delete(old) }
        updated.cropped = stored
        updated.crop = region
        updated.quarterTurns = quarterTurns
        return updated
    }

    func remove(_ photo: CoinPhoto) {
        media.delete(photo.allFiles)
    }
}
