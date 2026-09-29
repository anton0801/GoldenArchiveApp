//
//  GoalsHubView.swift
//  GoldenArchive
//
//  Presentation layer — Collection Goals, Value Notes and Exhibitions.
//  Goal progress comes from linked records; values are dated references
//  with a source; exhibitions stay local unless the user shares an export.
//

import SwiftUI

enum GoalsHubTab: String, CaseIterable, Identifiable {
    case goals, values, exhibition
    var id: String { rawValue }
    var title: String {
        switch self {
        case .goals: return "Goals"
        case .values: return "Value Notes"
        case .exhibition: return "Exhibition"
        }
    }
}

struct GoalsHubView: View {
    let container: AppContainer
    @State var tab: GoalsHubTab = .goals

    var body: some View {
        VStack(spacing: 0) {
            GASegmented(options: GoalsHubTab.allCases, selection: $tab) { $0.title }
                .padding(.horizontal, GATheme.gutter)
                .padding(.vertical, 8)
            switch tab {
            case .goals: GoalsView(container: container)
            case .values: ValueNotesListView(container: container, coinID: nil, embedded: true)
            case .exhibition: ExhibitionsView(container: container)
            }
        }
        .gaBackground()
        .navigationTitle("Goals & Showcase")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Goals

struct GoalSummary: Identifiable {
    var goal: CollectionGoal
    var progress: GoalProgress
    var id: UUID { goal.id }
}

@MainActor
final class GoalsViewModel: ArchiveViewModel {
    @Published private(set) var goals: [GoalSummary] = []

    override init(container: AppContainer) {
        super.init(container: container)
        reload()
    }

    override func reload() {
        let sets = container.sets.sets(includeArchived: true)
        let coins = container.coins.coins(includeArchived: true)
        let groups = container.duplicates.groups()
        goals = container.goals.goals().map { GoalSummary(goal: $0, progress: GoalUseCase.progress(for: $0, sets: sets, coins: coins, groups: groups)) }
    }

    func delete(_ id: UUID) { container.goalUseCase.delete(id: id) }
}

struct GoalsView: View {
    let container: AppContainer
    @StateObject private var model: GoalsViewModel
    @State private var editing: EditingGoal?

    struct EditingGoal: Identifiable {
        let id = UUID()
        var goal: CollectionGoal?
    }

    init(container: AppContainer) {
        self.container = container
        _model = StateObject(wrappedValue: GoalsViewModel(container: container))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    ArtworkView(artwork: .wishlistCase)
                        .frame(width: 120, height: 100)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Collection Goals")
                            .font(GAFont.title(.headline))
                            .foregroundColor(GAColor.text)
                        Text("Progress is counted from linked sets and items — never typed in.")
                            .font(.footnote)
                            .foregroundColor(GAColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Create Goal") { editing = EditingGoal(goal: nil) }
                            .buttonStyle(.ga(.primary, compact: true, fullWidth: false))
                    }
                }
                if model.goals.isEmpty {
                    EmptyStateView(title: "No goals yet", message: "Set a goal to finish a set by a date, or to reach a number of items in a collection.")
                }
                ForEach(model.goals) { summary in
                    goalCard(summary)
                }
            }
            .padding(GATheme.gutter)
            .padding(.bottom, 24)
        }
        .sheet(item: $editing) { item in
            GoalEditorSheet(container: container, goal: item.goal)
        }
    }

    private func goalCard(_ summary: GoalSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.goal.title).font(.headline).foregroundColor(GAColor.text)
                    Text(summary.progress.detail).font(.footnote).foregroundColor(GAColor.textSecondary)
                }
                Spacer()
                if summary.progress.isComplete {
                    StatusPill(text: "Reached", tint: GAColor.success, symbol: "checkmark")
                } else {
                    Text("\(Int((summary.progress.fraction * 100).rounded()))%")
                        .font(GAFont.number(.headline))
                        .foregroundColor(GAColor.bronzeText)
                }
            }
            GAProgressBar(value: summary.progress.fraction)
            HStack {
                if let date = summary.goal.targetDate {
                    let overdue = date < Date() && !summary.progress.isComplete
                    Label("Target \(GAFormat.day(date))", systemImage: "calendar")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(overdue ? GAColor.emberText : GAColor.textSecondary)
                }
                Spacer()
                Menu {
                    Button { editing = EditingGoal(goal: summary.goal) } label: { Label("Edit / Link Set", systemImage: "pencil") }
                    Button(role: .destructive) { model.delete(summary.goal.id) } label: { Label("Delete", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle").font(.title3).frame(width: 44, height: 44) }
                .accessibilityLabel("Goal actions")
            }
            if case .completeSets(let ids) = summary.goal.target, let first = ids.first {
                NavigationLink(destination: SetBuilderView(container: container, setID: first)) {
                    Text(ids.count == 1 ? "Open Set" : "Open First Set")
                        .font(.footnote.weight(.bold))
                        .foregroundColor(GAColor.bronzeText)
                }
            }
        }
        .gaCard()
    }
}

struct GoalEditorSheet: View {
    let container: AppContainer
    let goal: CollectionGoal?
    @Environment(\.dismiss) private var dismiss

    enum Kind: String, CaseIterable, Identifiable {
        case sets, count
        var id: String { rawValue }
    }

    @State private var title: String
    @State private var kind: Kind
    @State private var setIDs: Set<UUID>
    @State private var collectionID: UUID?
    @State private var target: Int
    @State private var targetDate: Date?
    @State private var note: String
    @State private var error: String?

    init(container: AppContainer, goal: CollectionGoal?) {
        self.container = container
        self.goal = goal
        _title = State(initialValue: goal?.title ?? "")
        _targetDate = State(initialValue: goal?.targetDate)
        _note = State(initialValue: goal?.note ?? "")
        switch goal?.target {
        case .itemCount(let collectionID, let target):
            _kind = State(initialValue: .count)
            _setIDs = State(initialValue: [])
            _collectionID = State(initialValue: collectionID)
            _target = State(initialValue: target)
        case .completeSets(let ids):
            _kind = State(initialValue: .sets)
            _setIDs = State(initialValue: Set(ids))
            _collectionID = State(initialValue: nil)
            _target = State(initialValue: 25)
        case nil:
            _kind = State(initialValue: .sets)
            _setIDs = State(initialValue: [])
            _collectionID = State(initialValue: nil)
            _target = State(initialValue: 25)
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    if let error { WarningNote(text: error) }
                    FormCard {
                        GATextField(title: "Goal", text: $title, prompt: "e.g. Finish the state quarters", required: true, capitalization: .sentences)
                        Picker("Goal type", selection: $kind) {
                            Text("Complete sets").tag(Kind.sets)
                            Text("Reach item count").tag(Kind.count)
                        }
                        .pickerStyle(.segmented)
                    }
                    if kind == .sets {
                        FormCard(title: "Link Set") {
                            let sets = container.sets.sets(includeArchived: false)
                            if sets.isEmpty {
                                Text("Create a set in Albums first.").font(.footnote).foregroundColor(GAColor.textSecondary)
                            }
                            ForEach(sets) { set in
                                Toggle(set.name, isOn: Binding(
                                    get: { setIDs.contains(set.id) },
                                    set: { if $0 { setIDs.insert(set.id) } else { setIDs.remove(set.id) } }
                                ))
                                .tint(GAColor.success)
                            }
                        }
                    } else {
                        FormCard(title: "Items") {
                            GAMenuPicker(title: "Count items in", selection: $collectionID,
                                         options: [(nil, "Whole archive")] + container.collections.collections(includeArchived: false).map { (Optional($0.id), $0.name) })
                            QuantityStepper(title: "Target number of items", value: $target, range: 1...100_000)
                        }
                    }
                    FormCard {
                        GAOptionalDateRow(title: "Target date", date: $targetDate, allowFuture: true)
                        GATextArea(title: "Note", text: $note, minHeight: 60)
                    }
                }
                .padding(GATheme.gutter)
            }
            .gaBackground()
            .navigationTitle(goal == nil ? "Create Goal" : "Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.font(.headline) }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func save() {
        guard !title.isBlank else { error = "Give the goal a name."; return }
        if kind == .sets && setIDs.isEmpty { error = "Link at least one set."; return }
        let now = Date()
        let targetValue: GoalTarget = kind == .sets
            ? .completeSets(container.sets.sets(includeArchived: true).map(\.id).filter { setIDs.contains($0) })
            : .itemCount(collectionID: collectionID, target: target)
        let value = CollectionGoal(
            id: goal?.id ?? UUID(),
            title: title,
            target: targetValue,
            targetDate: targetDate,
            note: note.trimmed,
            createdAt: goal?.createdAt ?? now,
            updatedAt: now
        )
        container.goalUseCase.save(value)
        dismiss()
    }
}

// MARK: - Value notes

@MainActor
final class ValueNotesViewModel: ArchiveViewModel {
    let coinID: UUID?
    @Published private(set) var notes: [ValueNote] = []
    @Published private(set) var names: [UUID: String] = [:]
    @Published private(set) var totals: [MoneyAmount] = []

    init(container: AppContainer, coinID: UUID?) {
        self.coinID = coinID
        super.init(container: container)
        reload()
    }

    override func reload() {
        notes = container.valueNotes.valueNotes(coinID: coinID)
        let coins = container.coins.coins(includeArchived: true)
        names = Dictionary(uniqueKeysWithValues: coins.map { ($0.id, $0.displayName) })
        let active = Set(coins.filter { !$0.isArchived }.map(\.id))
        totals = coinID == nil ? ValueNoteUseCase.referenceTotals(notes: notes, coinIDs: active) : []
    }

    func delete(_ id: UUID) { container.valueNoteUseCase.delete(id: id) }
}

struct ValueNotesListView: View {
    let container: AppContainer
    let coinID: UUID?
    var embedded = false
    @StateObject private var model: ValueNotesViewModel
    @State private var adding = false
    @State private var webLink: WebLink?

    init(container: AppContainer, coinID: UUID?, embedded: Bool = false) {
        self.container = container
        self.coinID = coinID
        self.embedded = embedded
        _model = StateObject(wrappedValue: ValueNotesViewModel(container: container, coinID: coinID))
    }

    var body: some View {
        let content = ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    ArtworkView(artwork: .wishlistCase)
                        .frame(width: 120, height: 100)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reference notes, not prices")
                            .font(GAFont.title(.headline))
                            .foregroundColor(GAColor.text)
                        Text("Each note keeps an amount, a source and a date. Values never update on their own and do not promise a sale price.")
                            .font(.footnote)
                            .foregroundColor(GAColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Add Value Note") { adding = true }
                            .buttonStyle(.ga(.primary, compact: true, fullWidth: false))
                    }
                }
                if !model.totals.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("REFERENCE NOTES TOTAL")
                            .font(.caption.weight(.heavy))
                            .tracking(1)
                            .foregroundColor(GAColor.bronzeText)
                        ForEach(model.totals, id: \.currency) { total in
                            Text(GAFormat.money(total)).font(GAFont.number(.title3)).foregroundColor(GAColor.text)
                        }
                        Text("Sum of the latest note per active item. Not an appraisal.")
                            .font(.caption)
                            .foregroundColor(GAColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .gaCard()
                }
                if model.notes.isEmpty {
                    EmptyStateView(title: "No value notes", message: "Add your own estimate or an external reference with its source and date.")
                }
                ForEach(model.notes) { note in noteCard(note) }
            }
            .padding(GATheme.gutter)
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $adding) {
            ValueNoteEditorSheet(container: container, coinID: coinID)
        }
        .sheet(item: $webLink) { link in SafariView(url: link.url).ignoresSafeArea() }

        if embedded {
            content
        } else {
            content
                .gaBackground()
                .navigationTitle("Value Notes")
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func noteCard(_ note: ValueNote) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(GAFormat.money(note.amount)).font(GAFont.number(.title3)).foregroundColor(GAColor.text)
                Spacer()
                StatusPill(text: note.kind.title, tint: note.kind == .externalReference ? GAColor.navy : GAColor.gold)
            }
            if coinID == nil {
                NavigationLink(destination: CoinDetailView(container: container, coinID: note.coinID)) {
                    Text(model.names[note.coinID] ?? "Deleted item")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(GAColor.bronzeText)
                }
            }
            Text("Source: \(note.sourceName) · \(GAFormat.day(note.valueDate))")
                .font(.footnote)
                .foregroundColor(GAColor.textSecondary)
            if !note.note.isBlank {
                Text(note.note).font(.footnote).foregroundColor(GAColor.text)
            }
            HStack {
                if let link = WebLink(note.sourceURL) {
                    Button("Open Source") { webLink = link }
                        .font(.footnote.weight(.bold))
                        .foregroundColor(GAColor.bronzeText)
                }
                Spacer()
                Button(role: .destructive) { model.delete(note.id) } label: {
                    Image(systemName: "trash").foregroundColor(GAColor.danger).frame(width: 44, height: 36)
                }
                .accessibilityLabel("Delete value note")
            }
        }
        .gaCard()
    }
}

struct ValueNoteEditorSheet: View {
    let container: AppContainer
    let coinID: UUID?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: AppRouter

    @State private var selectedCoinID: UUID?
    @State private var kind: ValueNoteKind = .externalReference
    @State private var amount = ""
    @State private var currency: String
    @State private var sourceName = ""
    @State private var sourceURL = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var error: String?

    init(container: AppContainer, coinID: UUID?) {
        self.container = container
        self.coinID = coinID
        _selectedCoinID = State(initialValue: coinID)
        _currency = State(initialValue: container.settings.settings().defaultCurrency)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    if let error { WarningNote(text: error) }
                    if coinID == nil {
                        FormCard(title: "Item") {
                            GAMenuPicker(title: "Item", selection: $selectedCoinID,
                                         options: [(nil, "Choose…")] + container.coins.coins(includeArchived: false).map { (Optional($0.id), $0.displayName) })
                        }
                    }
                    FormCard {
                        Picker("Kind", selection: $kind) { ForEach(ValueNoteKind.allCases) { Text($0.title).tag($0) } }
                            .pickerStyle(.segmented)
                        HStack(alignment: .top, spacing: 10) {
                            GATextField(title: "Amount", text: $amount, prompt: "0.00", required: true, keyboard: .decimalPad)
                            GATextField(title: "Currency", text: $currency, prompt: "USD", required: true, capitalization: .characters)
                                .frame(width: 100)
                        }
                        GATextField(title: "Source", text: $sourceName, prompt: kind == .personalEstimate ? "e.g. My own estimate" : "e.g. Price guide, 2026 edition", required: true)
                        GATextField(title: "Source link", text: $sourceURL, prompt: "https://… (optional)", keyboard: .URL, capitalization: .never)
                        GADateRow(title: "Value date", date: $date)
                        GATextArea(title: "Note", text: $note, prompt: "Condition it refers to, context…", minHeight: 60)
                    }
                    InfoNote(text: "A value note is a reference you record. It does not update automatically and is not an offer, appraisal or sale price.")
                }
                .padding(GATheme.gutter)
            }
            .gaBackground()
            .navigationTitle("Add Value Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.font(.headline) }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func save() {
        guard let target = selectedCoinID else {
            error = "Choose the item this note belongs to."
            return
        }
        switch container.valueNoteUseCase.add(coinID: target, kind: kind, amountText: amount, currency: currency, sourceName: sourceName, sourceURL: sourceURL, valueDate: date, note: note) {
        case .success:
            router.show("Value note saved", symbol: "note.text")
            dismiss()
        case .failure(let failure):
            error = failure.rawValue
        }
    }
}

// MARK: - Exhibition

@MainActor
final class ExhibitionsViewModel: ArchiveViewModel {
    @Published private(set) var exhibitions: [Exhibition] = []

    override init(container: AppContainer) {
        super.init(container: container)
        reload()
    }

    override func reload() { exhibitions = container.exhibitions.exhibitions() }
}

struct ExhibitionsView: View {
    let container: AppContainer
    @StateObject private var model: ExhibitionsViewModel
    @State private var creating = false

    init(container: AppContainer) {
        self.container = container
        _model = StateObject(wrappedValue: ExhibitionsViewModel(container: container))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    ArtworkView(artwork: .exhibitionWreath)
                        .frame(width: 160, height: 130)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your showcase")
                            .font(GAFont.title(.headline))
                            .foregroundColor(GAColor.text)
                        Text("A local presentation of chosen items. Nothing is published; export only when you decide.")
                            .font(.footnote)
                            .foregroundColor(GAColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Create Exhibition") { creating = true }
                            .buttonStyle(.ga(.primary, compact: true, fullWidth: false))
                    }
                }
                if model.exhibitions.isEmpty {
                    EmptyStateView(title: "No exhibitions yet", message: "Pick a few favourite items, add captions and arrange them in order.")
                }
                ForEach(model.exhibitions) { exhibition in
                    NavigationLink(destination: ExhibitionEditorView(container: container, exhibitionID: exhibition.id)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(exhibition.title).font(.headline).foregroundColor(GAColor.text)
                                Text("\(GAFormat.count(exhibition.items.count, "item")) · updated \(GAFormat.day(exhibition.updatedAt))")
                                    .font(.footnote)
                                    .foregroundColor(GAColor.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundColor(GAColor.textTertiary)
                        }
                        .gaCard()
                    }
                    .buttonStyle(PressableCardStyle())
                }
            }
            .padding(GATheme.gutter)
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $creating) {
            NewExhibitionSheet(container: container)
        }
    }
}

struct NewExhibitionSheet: View {
    let container: AppContainer
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var intro = ""
    @State private var coinIDs: [UUID] = []
    @State private var picking = false
    @State private var error: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    if let error { WarningNote(text: error) }
                    FormCard {
                        GATextField(title: "Exhibition title", text: $title, prompt: "e.g. Silver of the 1920s", required: true, capitalization: .words)
                        GATextArea(title: "Introduction", text: $intro, prompt: "A few words for your visitors", minHeight: 70)
                    }
                    FormCard(title: "Selected coins") {
                        let coins = coinIDs.compactMap { container.coins.coin(id: $0) }
                        if coins.isEmpty { Text("No items selected.").font(.footnote).foregroundColor(GAColor.textSecondary) }
                        ForEach(coins) { CoinRow(coin: $0, showsChevron: false) }
                        Button { picking = true } label: { Label("Choose Items", systemImage: "checklist") }
                            .buttonStyle(.ga(.quiet, compact: true))
                    }
                }
                .padding(GATheme.gutter)
            }
            .gaBackground()
            .navigationTitle("Create Exhibition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        guard !title.isBlank else { error = "Give the exhibition a title."; return }
                        guard !coinIDs.isEmpty else { error = "Choose at least one item."; return }
                        container.exhibitionUseCase.create(title: title, intro: intro, coinIDs: coinIDs)
                        dismiss()
                    }
                    .font(.headline)
                }
            }
            .sheet(isPresented: $picking) {
                LinkItemsSheet(container: container, selected: Set(coinIDs)) { coinIDs = $0 }
            }
        }
        .navigationViewStyle(.stack)
    }
}

@MainActor
final class ExhibitionEditorViewModel: ArchiveViewModel {
    let exhibitionID: UUID
    @Published var exhibition: Exhibition?
    @Published private(set) var coins: [UUID: Coin] = [:]
    @Published var exportError: String?

    init(container: AppContainer, exhibitionID: UUID) {
        self.exhibitionID = exhibitionID
        super.init(container: container)
        reload()
    }

    override func reload() {
        exhibition = container.exhibitions.exhibition(id: exhibitionID)
        coins = Dictionary(uniqueKeysWithValues: container.coins.coins(includeArchived: true).map { ($0.id, $0) })
    }

    func save(_ value: Exhibition) { container.exhibitionUseCase.save(value) }
    func delete() { container.exhibitionUseCase.delete(id: exhibitionID) }

    func export(pdf: Bool) -> URL? {
        guard let exhibition else { return nil }
        do {
            return pdf
                ? try container.exporter.exportPDF(exhibition, coins: coins, units: units)
                : try container.exporter.exportImage(exhibition, coins: coins, units: units)
        } catch {
            exportError = "The export could not be created. \(error.localizedDescription)"
            return nil
        }
    }
}

struct ExhibitionEditorView: View {
    let container: AppContainer
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ExhibitionEditorViewModel
    @State private var reordering = false
    @State private var picking = false
    @State private var share: ShareItem?
    @State private var confirmDelete = false
    @State private var exporting = false

    init(container: AppContainer, exhibitionID: UUID) {
        self.container = container
        _model = StateObject(wrappedValue: ExhibitionEditorViewModel(container: container, exhibitionID: exhibitionID))
    }

    var body: some View {
        Group {
            if let exhibition = model.exhibition {
                content(exhibition)
            } else {
                EmptyStateView(title: "Exhibition not found", message: "It was deleted.").padding(GATheme.gutter)
            }
        }
        .gaBackground()
        .navigationTitle(model.exhibition?.title ?? "Exhibition")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { picking = true } label: { Label("Choose Items", systemImage: "checklist") }
                    Button { reordering = true } label: { Label("Reorder", systemImage: "arrow.up.arrow.down") }
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete Exhibition", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle").font(.title3).frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel("Exhibition actions")
            }
        }
        .sheet(isPresented: $picking) {
            LinkItemsSheet(container: container, selected: Set(model.exhibition?.items.map(\.coinID) ?? [])) { ids in
                guard var exhibition = model.exhibition else { return }
                let existing = Dictionary(uniqueKeysWithValues: exhibition.items.map { ($0.coinID, $0) })
                let kept = exhibition.items.filter { ids.contains($0.coinID) }
                let added = ids.filter { existing[$0] == nil }.map { ExhibitItem(id: UUID(), coinID: $0, caption: "") }
                exhibition.items = kept + added
                model.save(exhibition)
            }
        }
        .sheet(isPresented: $reordering) {
            if let exhibition = model.exhibition {
                ReorderExhibitSheet(exhibition: exhibition, coins: model.coins) { model.save($0) }
            }
        }
        .sheet(item: $share) { item in ShareSheet(items: item.items).ignoresSafeArea() }
        .confirmationDialog("Delete this exhibition?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Exhibition", role: .destructive) {
                model.delete()
                dismiss()
            }
        } message: {
            Text("Only the presentation is removed. The items stay in your archive.")
        }
        .alert("Export failed", isPresented: Binding(get: { model.exportError != nil }, set: { if !$0 { model.exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.exportError ?? "") }
    }

    private func content(_ exhibition: Exhibition) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FormCard {
                    GATextField(title: "Title", text: Binding(get: { exhibition.title }, set: { value in
                        var copy = exhibition; copy.title = value; model.exhibition = copy
                    }), capitalization: .words)
                    GATextArea(title: "Introduction", text: Binding(get: { exhibition.intro }, set: { value in
                        var copy = exhibition; copy.intro = value; model.exhibition = copy
                    }), minHeight: 60)
                    Button("Save Text") {
                        if let current = model.exhibition, !current.title.isBlank { model.save(current) }
                    }
                    .buttonStyle(.ga(.quiet, compact: true))
                }

                SectionHeader(title: "Items & captions", subtitle: "In presentation order")
                ForEach(Array(exhibition.items.enumerated()), id: \.element.id) { index, item in
                    if let coin = model.coins[item.coinID] {
                        ExhibitItemRow(index: index + 1, coin: coin, caption: item.caption) { caption in
                            guard var copy = model.exhibition, let i = copy.items.firstIndex(where: { $0.id == item.id }) else { return }
                            copy.items[i].caption = caption
                            model.save(copy)
                        }
                    }
                }
                if exhibition.items.isEmpty {
                    EmptyStateView(title: "No items", message: "Choose items to show.", actionTitle: "Choose Items") { picking = true }
                }

                VStack(spacing: 10) {
                    Button {
                        exporting = true
                        if let url = model.export(pdf: true) { share = ShareItem(items: [url]) }
                        exporting = false
                    } label: { Label("Export PDF", systemImage: "doc.richtext") }
                    .buttonStyle(.gaPrimary)
                    Button {
                        if let url = model.export(pdf: false) { share = ShareItem(items: [url]) }
                    } label: { Label("Export Image", systemImage: "photo") }
                    .buttonStyle(.gaOutline)
                    Text("Exports are created on this device. They leave it only if you choose where to share them.")
                        .font(.caption)
                        .foregroundColor(GAColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .disabled(exhibition.items.isEmpty || exporting)
            }
            .padding(GATheme.gutter)
            .padding(.bottom, 24)
        }
    }
}

struct ExhibitItemRow: View {
    var index: Int
    var coin: Coin
    @State var caption: String
    var onSave: (String) -> Void
    @State private var edited = false

    init(index: Int, coin: Coin, caption: String, onSave: @escaping (String) -> Void) {
        self.index = index
        self.coin = coin
        self.onSave = onSave
        _caption = State(initialValue: caption)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("\(index)")
                    .font(GAFont.number(.headline))
                    .foregroundColor(GAColor.navy)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(GAColor.gold.opacity(0.9)))
                CoinRow(coin: coin, showsChevron: false)
            }
            HStack(spacing: 8) {
                TextField("Caption", text: $caption)
                    .onChange(of: caption) { _ in edited = true }
                    .inputChrome()
                if edited {
                    Button("Save") {
                        onSave(caption.trimmed)
                        edited = false
                    }
                    .buttonStyle(.ga(.secondary, compact: true, fullWidth: false))
                }
            }
        }
        .gaCard(padding: 12)
    }
}

struct ReorderExhibitSheet: View {
    let exhibition: Exhibition
    let coins: [UUID: Coin]
    var onSave: (Exhibition) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var items: [ExhibitItem] = []

    var body: some View {
        NavigationView {
            List {
                ForEach(items) { item in
                    Text(coins[item.coinID]?.displayName ?? "Item")
                }
                .onMove { items.move(fromOffsets: $0, toOffset: $1) }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var copy = exhibition
                        copy.items = items
                        onSave(copy)
                        dismiss()
                    }
                    .font(.headline)
                }
            }
            .onAppear { items = exhibition.items }
        }
        .navigationViewStyle(.stack)
    }
}
