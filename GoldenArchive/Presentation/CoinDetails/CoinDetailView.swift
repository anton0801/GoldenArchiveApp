//
//  CoinDetailView.swift
//  GoldenArchive
//
//  Presentation layer — the full record: the user's photos, attributes,
//  sets, condition, provenance, value notes and change history.
//

import SwiftUI

@MainActor
final class CoinDetailViewModel: ArchiveViewModel {
    let coinID: UUID

    @Published private(set) var coin: Coin?
    @Published private(set) var collectionName = "Unsorted"
    @Published private(set) var slots: [(set: CoinSet, slot: SetSlot)] = []
    @Published private(set) var documents: [ProvenanceDocument] = []
    @Published private(set) var latestObservation: ConditionObservation?
    @Published private(set) var observationCount = 0
    @Published private(set) var valueNotes: [ValueNote] = []
    @Published private(set) var duplicateGroup: DuplicateGroup?
    @Published private(set) var groupMembers: [Coin] = []

    init(container: AppContainer, coinID: UUID) {
        self.coinID = coinID
        super.init(container: container)
        reload()
    }

    override func reload() {
        coin = container.coins.coin(id: coinID)
        guard let coin else { return }
        collectionName = coin.collectionID.flatMap { container.collections.collection(id: $0)?.name } ?? "Unsorted"
        slots = container.linkSlot.slots(for: coinID)
        documents = container.documents.documents().filter { $0.linkedCoinIDs.contains(coinID) }
        let observations = container.conditions.observations(coinID: coinID)
        latestObservation = observations.first
        observationCount = observations.count
        valueNotes = container.valueNotes.valueNotes(coinID: coinID)
        duplicateGroup = container.duplicates.groups().first { $0.coinIDs.contains(coinID) }
        groupMembers = duplicateGroup?.coinIDs.filter { $0 != coinID }.compactMap { container.coins.coin(id: $0) } ?? []
    }

    func markReviewed() { container.coinState.markReviewed(coinID: coinID) }
    func archive() { container.coinState.archive(coinID: coinID) }
    func restore() { container.coinState.restore(coinID: coinID) }
    func deletionImpact() -> CoinDeletionImpact? { container.deleteCoin.impact(coinID: coinID) }
    func delete(alsoDocuments: Bool) { container.deleteCoin.execute(coinID: coinID, alsoDeleteExclusiveDocuments: alsoDocuments) }
    func updatePhotos(_ photos: [CoinPhoto]) { container.coinState.updatePhotos(coinID: coinID, photos: photos) }
    func unlink(_ reference: SlotReference) { container.linkSlot.unlink(reference) }
}

struct CoinDetailView: View {
    let container: AppContainer
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: CoinDetailViewModel

    @State private var sheet: DetailSheet?
    @State private var viewing: CoinPhoto?
    @State private var deletion: CoinDeletionImpact?
    @State private var webLink: WebLink?

    enum DetailSheet: String, Identifiable {
        case edit, photos, move, addToSet, duplicate, valueNote, document
        var id: String { rawValue }
    }

    init(container: AppContainer, coinID: UUID) {
        self.container = container
        _model = StateObject(wrappedValue: CoinDetailViewModel(container: container, coinID: coinID))
    }

    var body: some View {
        Group {
            if let coin = model.coin {
                content(coin)
            } else {
                EmptyStateView(title: "Item not found", message: "This item was deleted.")
                    .padding(GATheme.gutter)
            }
        }
        .gaBackground()
        .navigationTitle(model.coin?.displayName ?? "Item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let coin = model.coin { actionsMenu(coin) }
            }
        }
        .sheet(item: $sheet) { sheet in
            sheetView(sheet)
                .environmentObject(container)
                .environmentObject(router)
        }
        .sheet(item: $deletion) { impact in
            DeleteCoinSheet(impact: impact, onArchive: {
                deletion = nil
                model.archive()
                router.show("Moved to Archive", symbol: "archivebox.fill")
            }, onDelete: { alsoDocuments in
                deletion = nil
                model.delete(alsoDocuments: alsoDocuments)
                router.show("Item deleted", symbol: "trash.fill")
                dismiss()
            })
        }
        .fullScreenCover(item: $viewing) { photo in
            PhotoViewer(photo: photo) { viewing = nil }
                .environmentObject(container)
        }
        .sheet(item: $webLink) { link in SafariView(url: link.url).ignoresSafeArea() }
    }

    @ViewBuilder
    private func sheetView(_ sheet: DetailSheet) -> some View {
        if let coin = model.coin {
            switch sheet {
            case .edit:
                CoinEditSheet(container: container, coin: coin)
            case .photos:
                ManagePhotosSheet(container: container, coin: coin) { model.updatePhotos($0) }
            case .move:
                MoveItemsSheet(container: container, coinIDs: [coin.id], currentCollectionID: coin.collectionID)
            case .addToSet:
                AddToSetSheet(container: container, coinID: coin.id)
            case .duplicate:
                MarkDuplicateSheet(container: container, coinID: coin.id)
            case .valueNote:
                ValueNoteEditorSheet(container: container, coinID: coin.id)
            case .document:
                DocumentEditorSheet(container: container, documentID: nil, presetCoinIDs: [coin.id])
            }
        }
    }

    private func actionsMenu(_ coin: Coin) -> some View {
        Menu {
            Button { sheet = .edit } label: { Label("Edit", systemImage: "pencil") }
            Button { sheet = .photos } label: { Label("Manage Photos", systemImage: "camera") }
            Button { sheet = .document } label: { Label("Add Document", systemImage: "doc.badge.plus") }
            Button { sheet = .move } label: { Label("Move Collection", systemImage: "folder") }
            Button { sheet = .addToSet } label: { Label("Add to Set", systemImage: "square.grid.3x3") }
            Button { sheet = .duplicate } label: { Label("Mark Duplicate", systemImage: "square.on.square") }
            Button { sheet = .valueNote } label: { Label("Add Value Note", systemImage: "note.text.badge.plus") }
            Divider()
            if coin.isArchived {
                Button { model.restore() } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
            } else {
                Button {
                    model.archive()
                    router.show("Moved to Archive", symbol: "archivebox.fill")
                } label: { Label("Archive", systemImage: "archivebox") }
            }
            Button(role: .destructive) { deletion = model.deletionImpact() } label: { Label("Delete", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Item actions")
    }

    // MARK: Content

    private func content(_ coin: Coin) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                photoSection(coin)
                titleSection(coin)
                if coin.isArchived {
                    InfoNote(text: "This item is archived: hidden from Home, reports and goals. Restore it from the menu.", symbol: "archivebox")
                }
                if coin.needsReview { reviewBanner(coin) }
                characteristics(coin)
                archiveSection(coin)
                conditionSection
                provenanceSection
                valueSection
                duplicateSection
                if let reference = coin.catalogReference { referenceSection(reference) }
                if !coin.notes.isBlank || !coin.tags.isEmpty { notesSection(coin) }
                historySection(coin)
            }
            .padding(GATheme.gutter)
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func photoSection(_ coin: Coin) -> some View {
        if coin.photos.isEmpty {
            VStack(spacing: 10) {
                ArtworkView(artwork: .homeGuardian)
                    .frame(width: 160, height: 160)
                    .accessibilityHidden(true)
                Text("No photos yet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(GAColor.textSecondary)
                Button {
                    sheet = .photos
                } label: {
                    Label("Add Photos", systemImage: "camera.fill")
                }
                .buttonStyle(.ga(.secondary, compact: true, fullWidth: false))
            }
            .frame(maxWidth: .infinity)
            .gaCard()
        } else {
            VStack(spacing: 8) {
                TabView {
                    ForEach(coin.sortedPhotos) { photo in
                        Button { viewing = photo } label: {
                            ZStack(alignment: .bottomLeading) {
                                StoredImageView(file: photo.displayFile, maxPixel: 900, contentMode: .fit)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                Text(photo.side.title)
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(GAColor.cream)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(GAColor.navy.opacity(0.85)))
                                    .padding(10)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(photo.side.title) photo. Double-tap to view full screen.")
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: coin.photos.count > 1 ? .always : .never))
                .frame(height: 300)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(GAColor.stroke, lineWidth: 1))
                HStack {
                    Text("Your photos are shown unfiltered.")
                        .font(.caption)
                        .foregroundColor(GAColor.textSecondary)
                    Spacer()
                    Button("Manage Photos") { sheet = .photos }
                        .font(.footnote.weight(.bold))
                        .foregroundColor(GAColor.bronzeText)
                }
            }
        }
    }

    private func titleSection(_ coin: Coin) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(coin.displayName)
                .font(GAFont.display(.title))
                .foregroundColor(GAColor.text)
                .fixedSize(horizontal: false, vertical: true)
            if !coin.subtitle.isEmpty {
                Text(coin.subtitle)
                    .font(.body)
                    .foregroundColor(GAColor.textSecondary)
            }
            HStack(spacing: 6) {
                StatusPill(text: coin.kind.title, tint: GAColor.navy)
                StatusPill(text: "Qty \(coin.quantity)", tint: GAColor.bronze)
                if model.duplicateGroup != nil { StatusPill(text: "Duplicate group", tint: GAColor.silver, symbol: "square.on.square") }
            }
        }
    }

    private func reviewBanner(_ coin: Coin) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WarningNote(text: coin.reviewReason.isBlank ? "Marked for review." : coin.reviewReason, symbol: "exclamationmark.circle.fill")
            HStack(spacing: 10) {
                Button("Edit Details") { sheet = .edit }
                    .buttonStyle(.ga(.outline, compact: true))
                Button("Mark Reviewed") {
                    model.markReviewed()
                    router.show("Marked as reviewed")
                }
                .buttonStyle(.ga(.secondary, compact: true))
            }
        }
    }

    private func characteristics(_ coin: Coin) -> some View {
        let units = model.units
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                SectionHeader(title: "Characteristics")
                Button("Edit") { sheet = .edit }
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(GAColor.bronzeText)
            }
            .padding(.bottom, 4)
            KeyValueRow(label: "Country", value: coin.country)
            KeyValueRow(label: "Year", value: coin.year.map(YearText.display) ?? "")
            KeyValueRow(label: "Denomination", value: coin.denomination)
            KeyValueRow(label: "Mint", value: coin.mint)
            KeyValueRow(label: "Material", value: coin.material)
            KeyValueRow(label: "Diameter", value: units.diameterText(coin.diameterMM) ?? "")
            KeyValueRow(label: "Weight", value: units.weightText(coin.weightGrams) ?? "")
            KeyValueRow(label: "Edge", value: coin.edge)
            KeyValueRow(label: "Condition", value: coin.condition, placeholder: "No note")
        }
        .gaCard()
    }

    private func archiveSection(_ coin: Coin) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "In Your Archive")
            Button { sheet = .move } label: {
                ActionRowLabel(title: "Collection", subtitle: model.collectionName, symbol: "folder.fill", tint: GAColor.navy, trailing: "Move")
            }
            .buttonStyle(.plain)
            Divider()
            if model.slots.isEmpty {
                Button { sheet = .addToSet } label: {
                    ActionRowLabel(title: "Set slot", subtitle: "Not placed in any set", symbol: "square.grid.3x3.fill", tint: GAColor.bronze, trailing: "Add")
                }
                .buttonStyle(.plain)
            } else {
                ForEach(model.slots, id: \.slot.id) { pair in
                    NavigationLink(destination: SetBuilderView(container: container, setID: pair.set.id)) {
                        ActionRowLabel(title: pair.set.name, subtitle: "Slot: \(pair.slot.displayTitle)", symbol: "square.grid.3x3.fill", tint: GAColor.bronze)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) { model.unlink(SlotReference(setID: pair.set.id, slotID: pair.slot.id)) } label: {
                            Label("Unlink", systemImage: "link.badge.plus")
                        }
                    }
                }
                Button("Add to Another Set") { sheet = .addToSet }
                    .font(.footnote.weight(.bold))
                    .foregroundColor(GAColor.bronzeText)
            }
        }
        .gaCard()
    }

    private var conditionSection: some View {
        NavigationLink(destination: ConditionNotesView(container: container, coinID: model.coinID)) {
            VStack(alignment: .leading, spacing: 8) {
                ActionRowLabel(
                    title: "Condition Notes",
                    subtitle: model.latestObservation.map { "\(GAFormat.day($0.observedOn)) · \($0.wear.title)\($0.userGrade.isBlank ? "" : " · \($0.userGrade)")" } ?? "No observations yet",
                    symbol: "eye.fill",
                    tint: GAColor.navy,
                    trailing: model.observationCount > 0 ? "\(model.observationCount)" : nil
                )
            }
            .gaCard()
        }
        .buttonStyle(PressableCardStyle())
    }

    private var provenanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Provenance")
                Button("Add Document") { sheet = .document }
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(GAColor.bronzeText)
            }
            if model.documents.isEmpty {
                Text("Receipts, certificates and old records you attach appear here.")
                    .font(.footnote)
                    .foregroundColor(GAColor.textSecondary)
            } else {
                ForEach(model.documents) { document in
                    NavigationLink(destination: DocumentDetailView(container: container, documentID: document.id)) {
                        DocumentRow(document: document)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .gaCard()
    }

    private var valueSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Value Notes")
                Button("Add Value Note") { sheet = .valueNote }
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(GAColor.bronzeText)
            }
            if let latest = model.valueNotes.first {
                VStack(alignment: .leading, spacing: 4) {
                    Text(GAFormat.money(latest.amount))
                        .font(GAFont.number(.title3))
                        .foregroundColor(GAColor.text)
                    Text("\(latest.kind.title) · \(latest.sourceName) · \(GAFormat.day(latest.valueDate))")
                        .font(.footnote)
                        .foregroundColor(GAColor.textSecondary)
                }
                NavigationLink(destination: ValueNotesListView(container: container, coinID: model.coinID)) {
                    Text("All \(model.valueNotes.count) note\(model.valueNotes.count == 1 ? "" : "s")")
                        .font(.footnote.weight(.bold))
                        .foregroundColor(GAColor.bronzeText)
                }
            } else {
                Text("No value notes. A value note is a dated reference with a source — never a sale price.")
                    .font(.footnote)
                    .foregroundColor(GAColor.textSecondary)
            }
        }
        .gaCard()
    }

    @ViewBuilder
    private var duplicateSection: some View {
        if let group = model.duplicateGroup {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Duplicates")
                Text("Grouped with \(model.groupMembers.map(\.displayName).joined(separator: ", ")).")
                    .font(.footnote)
                    .foregroundColor(GAColor.textSecondary)
                NavigationLink(destination: DuplicateGroupView(container: container, groupID: group.id)) {
                    Text("Open Group")
                }
                .buttonStyle(.ga(.outline, compact: true, fullWidth: false))
            }
            .gaCard()
        }
    }

    private func referenceSection(_ reference: CatalogReference) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Catalog Reference")
            Text(reference.title).font(.body.weight(.semibold)).foregroundColor(GAColor.text)
            Text("\(reference.sourceName) · \(reference.matchLabel) · retrieved \(GAFormat.day(reference.retrievedAt))")
                .font(.footnote)
                .foregroundColor(GAColor.textSecondary)
            Text("A reference you chose. The identification is yours.")
                .font(.caption)
                .foregroundColor(GAColor.textSecondary)
            if let url = reference.url, let link = WebLink(url) {
                Button("Open Source") { webLink = link }
                    .font(.footnote.weight(.bold))
                    .foregroundColor(GAColor.bronzeText)
            }
        }
        .gaCard()
    }

    private func notesSection(_ coin: Coin) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Notes & Tags")
            if !coin.notes.isBlank {
                Text(coin.notes).font(.body).foregroundColor(GAColor.text).fixedSize(horizontal: false, vertical: true)
            }
            if !coin.tags.isEmpty { TagChipsView(tags: coin.tags) }
        }
        .gaCard()
    }

    private func historySection(_ coin: Coin) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "History")
            ForEach(coin.history.reversed()) { entry in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(GAColor.gold).frame(width: 8, height: 8).padding(.top, 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.summary).font(.subheadline).foregroundColor(GAColor.text)
                        Text(GAFormat.dateTime(entry.date)).font(.caption).foregroundColor(GAColor.textSecondary)
                    }
                }
            }
        }
        .gaCard()
    }
}

extension CoinDeletionImpact: Identifiable {
    var id: UUID { coin.id }
}

/// Lists everything the deletion touches. Documents are kept unless the
/// user explicitly chooses to delete the ones linked only to this item.
struct DeleteCoinSheet: View {
    let impact: CoinDeletionImpact
    var onArchive: () -> Void
    var onDelete: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var alsoDocuments = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Delete “\(impact.coin.displayName)”?")
                        .font(GAFont.title(.title2))
                        .foregroundColor(GAColor.text)
                    Text("This cannot be undone. Here is everything linked to this item:")
                        .font(.subheadline)
                        .foregroundColor(GAColor.textSecondary)
                    VStack(alignment: .leading, spacing: 8) {
                        impactLine("photo", "\(GAFormat.count(impact.photoFileCount, "photo file")) will be deleted")
                        impactLine("eye", "\(GAFormat.count(impact.observationCount, "condition note")) (\(GAFormat.count(impact.closeUpFileCount, "close-up"))) will be deleted")
                        impactLine("note.text", "\(GAFormat.count(impact.valueNoteCount, "value note")) will be deleted")
                        impactLine("square.grid.3x3", impact.slots.isEmpty ? "Not in any set" : "\(GAFormat.count(impact.slots.count, "set slot")) will become empty: \(impact.slots.map { "\($0.setName) — \($0.slotTitle)" }.joined(separator: "; "))")
                        impactLine("doc.on.doc", impact.documentCount == 0 ? "No linked documents" : "\(GAFormat.count(impact.documentCount, "linked document")) — kept in Provenance, just unlinked")
                        if impact.duplicateGroupCount > 0 { impactLine("square.on.square", "Removed from its duplicate group") }
                        if impact.exhibitionCount > 0 { impactLine("building.columns", "Removed from \(GAFormat.count(impact.exhibitionCount, "exhibition"))") }
                    }
                    .gaCard()
                    if !impact.exclusiveDocuments.isEmpty {
                        GAToggleRow(
                            title: "Also delete \(GAFormat.count(impact.exclusiveDocuments.count, "document")) linked only to this item",
                            subtitle: impact.exclusiveDocuments.map(\.displayTitle).joined(separator: ", "),
                            isOn: $alsoDocuments
                        )
                        .gaCard()
                    }
                    Button("Delete Item") { onDelete(alsoDocuments) }
                        .buttonStyle(.gaDestructive)
                    if !impact.coin.isArchived {
                        Button("Archive Instead") { onArchive() }
                            .buttonStyle(.gaOutline)
                    }
                }
                .padding(GATheme.gutter)
            }
            .gaBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .navigationViewStyle(.stack)
    }

    private func impactLine(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundColor(GAColor.navy).frame(width: 22)
            Text(text).font(.subheadline).foregroundColor(GAColor.text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Photos of an existing item. Each change is saved at once, so the record
/// and the files on disk always agree.
struct ManagePhotosSheet: View {
    let container: AppContainer
    let coin: Coin
    var onChange: ([CoinPhoto]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var photos: [CoinPhoto]
    @State private var openLibrary = false

    init(container: AppContainer, coin: Coin, onChange: @escaping ([CoinPhoto]) -> Void) {
        self.container = container
        self.coin = coin
        self.onChange = onChange
        _photos = State(initialValue: coin.photos)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                PhotoSetEditor(container: container, photos: $photos, openLibraryOnAppear: $openLibrary)
                    .padding(GATheme.gutter)
            }
            .gaBackground()
            .navigationTitle("Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: photos) { newValue in onChange(newValue) }
        }
        .navigationViewStyle(.stack)
    }
}
