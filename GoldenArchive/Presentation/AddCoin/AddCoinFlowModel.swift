//
//  AddCoinFlowModel.swift
//  GoldenArchive
//
//  Presentation layer — state of one Add Coin draft. The draft has a stable
//  id, so pressing Save twice updates the same record instead of adding a
//  duplicate; nothing is written to the archive before Review & Save.
//

import Foundation
import Combine

@MainActor
final class AddCoinFlowModel: ObservableObject {

    enum Step: Hashable {
        case start
        case photos
        case identify
        case review
        case saved
    }

    enum SearchState: Equatable {
        case idle
        case searching
        case done
    }

    let container: AppContainer
    let request: AddCoinRequest

    @Published var path: [Step] = [.start]
    @Published private(set) var draftID = UUID()
    @Published var form = CoinForm()
    @Published var photos: [CoinPhoto] = []
    @Published var reference: CatalogReference?
    @Published var errors: [FieldError] = []
    @Published private(set) var isSaving = false
    @Published private(set) var outcome: SaveCoinOutcome?
    @Published private(set) var collections: [CoinCollection] = []
    @Published var openLibraryOnAppear = false
    @Published var slotMessage: String?

    // Identification review
    @Published var query = CatalogQuery()
    @Published var queryYearText = ""
    @Published private(set) var searchState: SearchState = .idle
    @Published private(set) var candidates: [AssessedCandidate] = []
    @Published private(set) var sourceErrors: [String: String] = [:]
    @Published private(set) var sourcesQueried: [String] = []
    @Published var selectedCandidateID: String?
    @Published private(set) var isConfirming = false
    @Published var detailWarning: String?

    private var initialForm = CoinForm()
    private var searchTask: Task<Void, Never>?

    init(container: AppContainer, request: AddCoinRequest) {
        self.container = container
        self.request = request
        collections = container.collections.collections(includeArchived: false)

        var form = CoinForm()
        form.kind = request.kind
        form.collectionID = request.collectionID
        if let name = request.prefillName { form.name = name }
        if let prefill = request.prefill {
            form.country = prefill.country
            if let year = prefill.year {
                form.yearText = "\(abs(year))"
                form.isBC = year < 0
            }
            form.denomination = prefill.denomination
            form.mint = prefill.mint
            form.material = prefill.material
        }
        self.form = form
        initialForm = form

        if let method = request.method { choose(method) }
    }

    var current: Step { path.last ?? .start }
    var canGoBack: Bool { path.count > 1 && current != .saved }
    var hasUnsavedWork: Bool { outcome == nil && (!photos.isEmpty || form != initialForm || reference != nil) }
    var units: MeasurementUnits { container.settings.settings().units }
    var catalogSources: [String] { container.catalog.activeSourceNames }

    var selectedCandidate: AssessedCandidate? {
        candidates.first { $0.id == selectedCandidateID }
    }

    // MARK: Navigation

    func choose(_ method: AddMethod) {
        switch method {
        case .takePhoto:
            push(.photos)
        case .choosePhoto:
            openLibraryOnAppear = true
            push(.photos)
        case .searchCatalog:
            prepareQueryFromForm()
            push(.identify)
        case .manual:
            push(.review)
        }
    }

    func push(_ step: Step) {
        guard current != step else { return }
        path.append(step)
    }

    func back() {
        guard canGoBack else { return }
        path.removeLast()
    }

    func continueFromPhotos() {
        prepareQueryFromForm()
        push(.identify)
    }

    func refreshCollections() {
        collections = container.collections.collections(includeArchived: false)
    }

    // MARK: Identification

    func prepareQueryFromForm() {
        query.kind = form.kind
        if query.country.isBlank { query.country = form.country }
        if query.denomination.isBlank { query.denomination = form.denomination }
        if query.mint.isBlank { query.mint = form.mint }
        if query.material.isBlank { query.material = form.material }
        if queryYearText.isBlank, !form.yearText.isBlank, !form.isBC { queryYearText = form.yearText }
        if query.text.isBlank { query.text = form.name }
    }

    var queryIsEmpty: Bool {
        var q = query
        q.year = Int(queryYearText.trimmed)
        return q.isEmpty
    }

    func search() {
        searchTask?.cancel()
        var q = query
        q.year = Int(queryYearText.trimmed)
        query.year = q.year
        guard !q.isEmpty else { return }
        searchState = .searching
        selectedCandidateID = nil
        let useCase = container.searchCatalog
        searchTask = Task { [weak self] in
            let (assessed, result) = await useCase.execute(q)
            guard let self, !Task.isCancelled else { return }
            self.candidates = assessed
            self.sourceErrors = result.sourceErrors
            self.sourcesQueried = result.sourcesQueried
            self.searchState = .done
        }
    }

    /// Loads full attributes for a remote candidate (for Compare / Confirm).
    func loadDetails(for id: String) async {
        guard let index = candidates.firstIndex(where: { $0.id == id }), !candidates[index].candidate.hasDetails else { return }
        do {
            let detailed = try await container.searchCatalog.details(for: candidates[index].candidate)
            guard let fresh = candidates.firstIndex(where: { $0.id == id }) else { return }
            var q = query
            q.year = Int(queryYearText.trimmed)
            candidates[fresh] = AssessedCandidate(candidate: detailed, assessment: MetadataMatcher.assess(detailed, against: q))
            detailWarning = nil
        } catch {
            detailWarning = "Details could not be loaded (\(error.localizedDescription)). Only the summary is shown."
        }
    }

    /// Applies what the user typed, then fills remaining blanks from the
    /// chosen reference, and opens Review & Save.
    func confirmDetails() async {
        guard let id = selectedCandidateID else { return }
        isConfirming = true
        await loadDetails(for: id)
        isConfirming = false
        guard let chosen = candidates.first(where: { $0.id == id }) else { return }
        applyQueryToForm()
        form.applyBlanks(from: chosen.candidate, units: units)
        reference = SearchCatalogUseCase.reference(for: chosen, at: container.clock.now)
        push(.review)
    }

    func noneMatch() {
        applyQueryToForm()
        selectedCandidateID = nil
        push(.review)
    }

    private func applyQueryToForm() {
        form.kind = query.kind
        if form.country.isBlank { form.country = query.country.trimmed }
        if form.denomination.isBlank { form.denomination = query.denomination.trimmed }
        if form.mint.isBlank { form.mint = query.mint.trimmed }
        if form.material.isBlank { form.material = query.material.trimmed }
        if form.yearText.isBlank, let year = Int(queryYearText.trimmed) { form.yearText = "\(year)" }
    }

    // MARK: Save

    func save() {
        guard !isSaving, outcome == nil else { return }
        isSaving = true
        defer { isSaving = false }
        let saveRequest = SaveCoinRequest(
            coinID: draftID,
            form: form,
            photos: photos,
            catalogReference: reference,
            pendingSlot: request.pendingSlot,
            fulfilledWishID: request.wishID
        )
        switch container.saveCoin.execute(saveRequest) {
        case .success(let result):
            errors = []
            outcome = result
            if case .needsQuantityConfirmation(let current, let required, _) = result.slotResult {
                slotMessage = "This record has quantity \(current) but the set slots need \(required). Confirm how many pieces you own to link it."
            } else if result.slotResult == .linked {
                slotMessage = "Linked to its set slot."
            }
            push(.saved)
        case .failure(let failure):
            errors = failure.errors
        }
    }

    func confirmSlotQuantity() {
        guard let coin = outcome?.coin, let slot = request.pendingSlot ?? wishSlot else { return }
        let result = container.linkSlot.execute(coinID: coin.id, slot: slot, confirmQuantity: true)
        slotMessage = result == .linked ? "Quantity confirmed and linked to its set slot." : "The slot could not be linked."
    }

    private var wishSlot: SlotReference? {
        request.wishID.flatMap { container.wishes.wish(id: $0)?.linkedSlot }
    }

    var needsSlotConfirmation: Bool {
        if case .needsQuantityConfirmation = outcome?.slotResult, slotMessage?.hasPrefix("This record") == true { return true }
        return false
    }

    func startAnother() {
        let collectionID = form.collectionID
        draftID = UUID()
        form = CoinForm()
        form.collectionID = collectionID
        initialForm = form
        photos = []
        reference = nil
        errors = []
        outcome = nil
        slotMessage = nil
        query = CatalogQuery()
        queryYearText = ""
        candidates = []
        searchState = .idle
        selectedCandidateID = nil
        path = [.start]
    }

    /// Cancelling removes photo files captured for this unsaved draft.
    func discardDraft() {
        searchTask?.cancel()
        guard outcome == nil else { return }
        let intake = container.photoIntake
        photos.forEach { intake.remove($0) }
        photos = []
    }
}
