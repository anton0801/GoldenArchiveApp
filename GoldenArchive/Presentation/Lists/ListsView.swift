//
//  ListsView.swift
//  GoldenArchive
//
//  Presentation layer — Duplicates and Wish List. Only the active tab's
//  artwork is shown. Nothing here is a marketplace: no offers, no trades.
//

import SwiftUI

struct ListsView: View {
    let container: AppContainer
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        VStack(spacing: 0) {
            GASegmented(options: ListsSegment.allCases, selection: $router.listsSegment) { $0.title }
                .padding(.horizontal, GATheme.gutter)
                .padding(.top, 8)
                .padding(.bottom, 4)
            switch router.listsSegment {
            case .duplicates: DuplicatesView(container: container)
            case .wishList: WishListView(container: container)
            }
        }
        .gaBackground()
        .navigationTitle("Lists")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Duplicates

struct DuplicateGroupSummary: Identifiable {
    var group: DuplicateGroup
    var coins: [Coin]
    var id: UUID { group.id }
}

@MainActor
final class DuplicatesViewModel: ArchiveViewModel {
    @Published private(set) var groups: [DuplicateGroupSummary] = []
    @Published private(set) var possible: [[Coin]] = []
    @Published private(set) var multiples: [Coin] = []

    override init(container: AppContainer) {
        super.init(container: container)
        reload()
    }

    override func reload() {
        let coins = container.coins.coins(includeArchived: true)
        let byID = Dictionary(uniqueKeysWithValues: coins.map { ($0.id, $0) })
        let rawGroups = container.duplicates.groups()
        groups = rawGroups.map { group in DuplicateGroupSummary(group: group, coins: group.coinIDs.compactMap { byID[$0] }) }
        possible = DuplicateFinder.possibleDuplicates(coins: coins, groups: rawGroups)
        multiples = coins.filter { !$0.isArchived && $0.quantity > 1 }.sorted { $0.quantity > $1.quantity }
    }

    func group(_ coins: [Coin]) { container.duplicateUseCase.createGroup(coinIDs: coins.map(\.id)) }

    var isEmpty: Bool { groups.isEmpty && possible.isEmpty && multiples.isEmpty }
}

struct DuplicatesView: View {
    let container: AppContainer
    @EnvironmentObject private var router: AppRouter
    @StateObject private var model: DuplicatesViewModel

    init(container: AppContainer) {
        self.container = container
        _model = StateObject(wrappedValue: DuplicatesViewModel(container: container))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 14) {
                    ArtworkView(artwork: .duplicateStacks)
                        .frame(width: 140, height: 110)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Personal duplicate list")
                            .font(GAFont.title(.headline))
                            .foregroundColor(GAColor.text)
                        Text("Group copies, decide what to keep and note extras — for your own records only.")
                            .font(.footnote)
                            .foregroundColor(GAColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if model.isEmpty {
                    EmptyStateView(title: "No duplicates", message: "Mark an item as a duplicate from its details, or raise its quantity. Records that look alike will be suggested here.")
                }

                if !model.groups.isEmpty {
                    SectionHeader(title: "Duplicate Groups")
                    ForEach(model.groups) { summary in
                        NavigationLink(destination: DuplicateGroupView(container: container, groupID: summary.id)) {
                            groupCard(summary)
                        }
                        .buttonStyle(PressableCardStyle())
                    }
                }

                if !model.possible.isEmpty {
                    SectionHeader(title: "Possible Duplicates", subtitle: "Same type, country, year, denomination and mint")
                    ForEach(model.possible.indices, id: \.self) { index in
                        let coins = model.possible[index]
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(coins) { coin in CoinRow(coin: coin, showsChevron: false) }
                            Button("Group as Duplicates") {
                                model.group(coins)
                                router.show("Grouped \(coins.count) records", symbol: "square.on.square")
                            }
                            .buttonStyle(.ga(.secondary, compact: true))
                        }
                        .gaCard(padding: 12)
                    }
                }

                if !model.multiples.isEmpty {
                    SectionHeader(title: "Several Pieces in One Record", subtitle: "Quantity above one")
                    ForEach(model.multiples) { coin in
                        NavigationLink(destination: CoinDetailView(container: container, coinID: coin.id)) {
                            CoinRow(coin: coin, trailing: "+\(coin.quantity - 1) extra").gaCard(padding: 10, radius: 16)
                        }
                        .buttonStyle(PressableCardStyle())
                    }
                }
            }
            .padding(GATheme.gutter)
            .padding(.bottom, 24)
        }
    }

    private func groupCard(_ summary: DuplicateGroupSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(summary.group.title).font(.headline).foregroundColor(GAColor.text).lineLimit(2)
                Spacer()
                if summary.group.reviewedAt != nil {
                    StatusPill(text: "Kept", tint: GAColor.success, symbol: "checkmark")
                } else if summary.group.members.contains(where: { $0.status == .undecided }) {
                    StatusPill(text: "Undecided", tint: GAColor.ember)
                }
            }
            HStack(spacing: -12) {
                ForEach(summary.coins.prefix(5)) { coin in
                    CoinThumbnail(coin: coin, size: 44)
                        .background(RoundedRectangle(cornerRadius: 11).fill(GAColor.card))
                }
            }
            Text("\(GAFormat.count(summary.coins.count, "record")) · \(summary.group.extraCount) marked extra · \(summary.coins.reduce(0) { $0 + $1.quantity }) pieces")
                .font(.footnote)
                .foregroundColor(GAColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gaCard()
    }
}

@MainActor
final class DuplicateGroupViewModel: ArchiveViewModel {
    let groupID: UUID
    @Published private(set) var group: DuplicateGroup?
    @Published private(set) var coins: [Coin] = []

    init(container: AppContainer, groupID: UUID) {
        self.groupID = groupID
        super.init(container: container)
        reload()
    }

    override func reload() {
        group = container.duplicates.group(id: groupID)
        coins = group?.coinIDs.compactMap { container.coins.coin(id: $0) } ?? []
    }

    func status(of coinID: UUID) -> KeepStatus { group?.members.first { $0.coinID == coinID }?.status ?? .undecided }
    func setStatus(_ coinID: UUID, _ status: KeepStatus) { container.duplicateUseCase.setStatus(groupID: groupID, coinID: coinID, status: status) }
    func keepAll() { container.duplicateUseCase.keepAll(groupID: groupID) }
    func remove(_ coinID: UUID) { container.duplicateUseCase.removeFromGroup(groupID: groupID, coinID: coinID) }
    func dissolve() { container.duplicateUseCase.dissolve(groupID: groupID) }
    func saveNote(_ note: String) { container.duplicateUseCase.updateNote(groupID: groupID, note: note) }
}

struct DuplicateGroupView: View {
    let container: AppContainer
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: DuplicateGroupViewModel
    @State private var merging = false
    @State private var note = ""
    @State private var confirmDissolve = false

    init(container: AppContainer, groupID: UUID) {
        self.container = container
        _model = StateObject(wrappedValue: DuplicateGroupViewModel(container: container, groupID: groupID))
    }

    var body: some View {
        Group {
            if let group = model.group {
                content(group)
            } else {
                EmptyStateView(title: "Group closed", message: "This duplicate group no longer exists. The items are kept.").padding(GATheme.gutter)
            }
        }
        .gaBackground()
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $merging) {
            MergeMetadataSheet(container: container, groupID: model.groupID, coins: model.coins)
                .environmentObject(router)
        }
        .confirmationDialog("Close this group?", isPresented: $confirmDissolve, titleVisibility: .visible) {
            Button("Close Group", role: .destructive) {
                model.dissolve()
                dismiss()
            }
        } message: {
            Text("The records stay in your archive; they are just no longer grouped.")
        }
        .onAppear { note = model.group?.note ?? "" }
    }

    private func content(_ group: DuplicateGroup) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(model.coins) { coin in compareColumn(coin) }
                    }
                    .padding(.vertical, 4)
                }

                HStack(spacing: 10) {
                    Button {
                        model.keepAll()
                        router.show("Every record kept", symbol: "checkmark.seal.fill")
                    } label: { Text(model.coins.count == 2 ? "Keep Both" : "Keep All") }
                    .buttonStyle(.ga(.secondary, compact: true))
                    Button("Merge Metadata") { merging = true }
                        .buttonStyle(.ga(.outline, compact: true))
                }
                InfoNote(text: "Merge Metadata copies attributes you choose between these records. Photos, documents, condition notes and value notes are never merged or deleted.")

                FormCard(title: "Group note") {
                    GATextArea(title: "Note", text: $note, prompt: "e.g. keep the sharper strike", minHeight: 60)
                    Button("Save Note") { model.saveNote(note) }
                        .buttonStyle(.ga(.quiet, compact: true))
                }

                Button("Close Group", role: .destructive) { confirmDissolve = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(GAColor.danger)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(GATheme.gutter)
        }
    }

    private func compareColumn(_ coin: Coin) -> some View {
        let status = model.status(of: coin.id)
        let units = model.units
        return VStack(alignment: .leading, spacing: 8) {
            NavigationLink(destination: CoinDetailView(container: container, coinID: coin.id)) {
                StoredImageView(file: coin.primaryPhoto?.displayFile, maxPixel: 360)
                    .frame(width: 170, height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            Text(coin.displayName).font(.subheadline.weight(.bold)).foregroundColor(GAColor.text).lineLimit(2)
            Group {
                Text("Year: \(coin.year.map(YearText.display) ?? "—")")
                Text("Mint: \(coin.mint.isBlank ? "—" : coin.mint)")
                Text("Material: \(coin.material.isBlank ? "—" : coin.material)")
                Text("Weight: \(units.weightText(coin.weightGrams) ?? "—")")
                Text("Condition: \(coin.condition.isBlank ? "—" : coin.condition)")
                Text("Quantity: \(coin.quantity)")
            }
            .font(.caption)
            .foregroundColor(GAColor.textSecondary)
            Menu {
                ForEach(KeepStatus.allCases) { option in
                    Button { model.setStatus(coin.id, option) } label: {
                        if option == status { Label(option.title, systemImage: "checkmark") } else { Text(option.title) }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Status:").font(.caption).foregroundColor(GAColor.textSecondary)
                    StatusPill(text: status.title, tint: status == .keep ? GAColor.success : (status == .extra ? GAColor.navy : GAColor.ember))
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundColor(GAColor.textSecondary)
                }
                .frame(minHeight: 36)
            }
            .accessibilityLabel("Keep status: \(status.title)")
            Button("Mark Extra") { model.setStatus(coin.id, .extra) }
                .font(.caption.weight(.bold))
                .foregroundColor(GAColor.bronzeText)
                .disabled(status == .extra)
            Button("Remove from group") { model.remove(coin.id) }
                .font(.caption.weight(.semibold))
                .foregroundColor(GAColor.danger)
        }
        .frame(width: 190)
        .gaCard(padding: 10, radius: 18)
    }
}

struct MergeMetadataSheet: View {
    let container: AppContainer
    let groupID: UUID
    let coins: [Coin]
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: AppRouter
    @State private var primaryID: UUID?
    @State private var fields: Set<MergeField> = [.country, .year, .denomination, .mint, .material, .diameter, .weight, .edge]
    @State private var overwrite = false

    private var units: MeasurementUnits { container.settings.settings().units }

    private var preview: [MergeChange] {
        guard let primaryID else { return [] }
        return container.duplicateUseCase.mergePreview(groupID: groupID, primaryID: primaryID, fields: fields, overwrite: overwrite, units: units)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    FormCard(title: "Copy from") {
                        ForEach(coins) { coin in
                            Button { primaryID = coin.id } label: {
                                HStack {
                                    Image(systemName: primaryID == coin.id ? "largecircle.fill.circle" : "circle")
                                        .foregroundColor(primaryID == coin.id ? GAColor.navy : GAColor.textTertiary)
                                    CoinRow(coin: coin, showsChevron: false)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    FormCard(title: "Attributes") {
                        ForEach(MergeField.allCases) { field in
                            Toggle(field.title, isOn: Binding(
                                get: { fields.contains(field) },
                                set: { if $0 { fields.insert(field) } else { fields.remove(field) } }
                            ))
                            .tint(GAColor.success)
                        }
                        GAToggleRow(title: "Overwrite filled fields", subtitle: "Off: only blank fields are filled.", isOn: $overwrite)
                    }
                    FormCard(title: "Preview", footer: "Photos, documents, condition notes and value notes are not affected.") {
                        if primaryID == nil {
                            Text("Choose the record to copy from.").font(.footnote).foregroundColor(GAColor.textSecondary)
                        } else if preview.isEmpty {
                            Text("Nothing would change.").font(.footnote).foregroundColor(GAColor.textSecondary)
                        } else {
                            ForEach(preview) { change in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(change.coinName) · \(change.field.title)").font(.footnote.weight(.semibold)).foregroundColor(GAColor.text)
                                    Text("\(change.from) → \(change.to)").font(.caption).foregroundColor(GAColor.textSecondary)
                                }
                            }
                        }
                    }
                }
                .padding(GATheme.gutter)
            }
            .gaBackground()
            .navigationTitle("Merge Metadata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        guard let primaryID else { return }
                        let count = container.duplicateUseCase.applyMerge(groupID: groupID, primaryID: primaryID, fields: fields, overwrite: overwrite, units: units)
                        router.show("Updated \(count) field\(count == 1 ? "" : "s")", symbol: "arrow.triangle.merge")
                        dismiss()
                    }
                    .font(.headline)
                    .disabled(preview.isEmpty)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

struct MarkDuplicateSheet: View {
    let container: AppContainer
    let coinID: UUID
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: AppRouter
    @State private var search = ""

    private var coin: Coin? { container.coins.coin(id: coinID) }

    private var others: [Coin] {
        let query = search.normalizedKey
        return container.coins.coins(includeArchived: false).filter { $0.id != coinID && (query.isEmpty || $0.searchText.contains(query)) }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if let coin {
                        let suggestions = DuplicateFinder.suggestions(for: coin, in: container.coins.coins(includeArchived: false))
                        if !suggestions.isEmpty && search.isEmpty {
                            SectionHeader(title: "Looks similar")
                            ForEach(suggestions) { other in row(other) }
                            SectionHeader(title: "All items")
                        }
                    }
                    ForEach(others) { other in row(other) }
                    if others.isEmpty {
                        EmptyStateView(title: "No other items", message: "A duplicate needs another record. If you own several identical pieces, raise the quantity instead.")
                    }
                }
                .padding(GATheme.gutter)
            }
            .gaBackground()
            .searchable(text: $search, prompt: "Search items")
            .navigationTitle("Duplicate of…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .navigationViewStyle(.stack)
    }

    private func row(_ other: Coin) -> some View {
        Button {
            container.duplicateUseCase.markDuplicate(coinID, of: other.id)
            router.show("Added to Duplicates", symbol: "square.on.square")
            dismiss()
        } label: {
            CoinRow(coin: other, showsChevron: false).gaCard(padding: 10, radius: 16)
        }
        .buttonStyle(PressableCardStyle())
    }
}

// MARK: - Wish list

@MainActor
final class WishListViewModel: ArchiveViewModel {
    @Published private(set) var wanted: [WishItem] = []
    @Published private(set) var acquired: [WishItem] = []
    @Published private(set) var slotTitles: [UUID: String] = [:]

    override init(container: AppContainer) {
        super.init(container: container)
        reload()
    }

    override func reload() {
        let all = container.wishes.wishes()
        wanted = all.filter { $0.status == .wanted }.sorted { $0.priority == $1.priority ? $0.createdAt > $1.createdAt : $0.priority > $1.priority }
        acquired = all.filter { $0.status == .acquired }.sorted { ($0.acquiredAt ?? $0.updatedAt) > ($1.acquiredAt ?? $1.updatedAt) }
        var titles: [UUID: String] = [:]
        for wish in all {
            if let ref = wish.linkedSlot, let set = container.sets.set(id: ref.setID), let slot = set.slots.first(where: { $0.id == ref.slotID }) {
                titles[wish.id] = "\(set.name) — \(slot.displayTitle)"
            }
        }
        slotTitles = titles
    }

    func remove(_ id: UUID) { container.wishUseCase.delete(id: id) }
    func reopen(_ id: UUID) { container.wishUseCase.reopen(id: id) }
}

struct WishListView: View {
    let container: AppContainer
    @EnvironmentObject private var router: AppRouter
    @StateObject private var model: WishListViewModel
    @State private var editing: EditingWish?
    @State private var webLink: WebLink?

    struct EditingWish: Identifiable {
        let id = UUID()
        var wish: WishItem?
    }

    init(container: AppContainer) {
        self.container = container
        _model = StateObject(wrappedValue: WishListViewModel(container: container))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 14) {
                    ArtworkView(artwork: .wishlistCase)
                        .frame(width: 140, height: 110)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(model.wanted.count) wanted")
                            .font(GAFont.title(.headline))
                            .foregroundColor(GAColor.text)
                        Text("Target prices are your own notes. Nothing is bought or sold in the app.")
                            .font(.footnote)
                            .foregroundColor(GAColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Add Wish") { editing = EditingWish(wish: nil) }
                            .buttonStyle(.ga(.primary, compact: true, fullWidth: false))
                    }
                }

                if model.wanted.isEmpty && model.acquired.isEmpty {
                    EmptyStateView(title: "Your wish list is empty", message: "Add items you are looking for, or send missing set slots here from a set.")
                }

                ForEach(model.wanted) { wish in wishCard(wish) }

                if !model.acquired.isEmpty {
                    SectionHeader(title: "Acquired")
                    ForEach(model.acquired) { wish in
                        HStack {
                            Image(systemName: "checkmark.seal.fill").foregroundColor(GAColor.success)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(wish.title).font(.subheadline.weight(.semibold)).foregroundColor(GAColor.text)
                                if let date = wish.acquiredAt {
                                    Text("Acquired \(GAFormat.day(date))").font(.caption).foregroundColor(GAColor.textSecondary)
                                }
                            }
                            Spacer()
                            if let coinID = wish.acquiredCoinID {
                                NavigationLink(destination: CoinDetailView(container: container, coinID: coinID)) {
                                    Text("Open").font(.footnote.weight(.bold)).foregroundColor(GAColor.bronzeText)
                                }
                            }
                            Menu {
                                Button { model.reopen(wish.id) } label: { Label("Mark as Wanted", systemImage: "arrow.uturn.backward") }
                                Button(role: .destructive) { model.remove(wish.id) } label: { Label("Remove", systemImage: "trash") }
                            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                        }
                        .gaCard(padding: 12, radius: 16)
                    }
                }
            }
            .padding(GATheme.gutter)
            .padding(.bottom, 24)
        }
        .sheet(item: $editing) { item in
            WishEditorSheet(container: container, wish: item.wish)
        }
        .sheet(item: $webLink) { link in SafariView(url: link.url).ignoresSafeArea() }
    }

    private func wishCard(_ wish: WishItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(wish.title).font(.headline).foregroundColor(GAColor.text)
                    if !wish.expected.summary.isEmpty {
                        Text(wish.expected.summary).font(.footnote).foregroundColor(GAColor.textSecondary)
                    }
                }
                Spacer()
                StatusPill(text: wish.priority.title, tint: wish.priority == .high ? GAColor.ember : (wish.priority == .medium ? GAColor.gold : GAColor.silver))
            }
            if !wish.targetNote.isBlank {
                Label("Target note: \(wish.targetNote)", systemImage: "scope")
                    .font(.footnote)
                    .foregroundColor(GAColor.text)
            }
            if let slot = model.slotTitles[wish.id] {
                Label(slot, systemImage: "square.grid.3x3")
                    .font(.footnote)
                    .foregroundColor(GAColor.bronzeText)
            }
            HStack(spacing: 8) {
                Button("Mark Acquired") {
                    router.startAddCoin(AddCoinRequest(prefill: wish.expected, prefillName: wish.title, kind: wish.kind, wishID: wish.id))
                }
                .buttonStyle(.ga(.primary, compact: true))
                Menu {
                    Button { editing = EditingWish(wish: wish) } label: { Label("Edit", systemImage: "pencil") }
                    if let link = WebLink(wish.sourceLink) {
                        Button { webLink = link } label: { Label("Open Source Link", systemImage: "safari") }
                    }
                    Button(role: .destructive) { model.remove(wish.id) } label: { Label("Remove", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Wish actions")
            }
            Text("Mark Acquired opens Add Coin with these details. The wish is closed only after you save the item.")
                .font(.caption2)
                .foregroundColor(GAColor.textTertiary)
        }
        .gaCard()
    }
}

struct WishEditorSheet: View {
    let container: AppContainer
    let wish: WishItem?
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WishItem
    @State private var yearText: String
    @State private var errors: [String] = []

    init(container: AppContainer, wish: WishItem?) {
        self.container = container
        self.wish = wish
        let now = Date()
        let value = wish ?? WishItem(title: "", createdAt: now, updatedAt: now)
        _draft = State(initialValue: value)
        _yearText = State(initialValue: value.expected.year.map { "\($0)" } ?? "")
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    if !errors.isEmpty { WarningNote(text: errors.joined(separator: " ")) }
                    FormCard {
                        GATextField(title: "Wanted item", text: $draft.title, prompt: "e.g. 1916-D Mercury dime", required: true, capitalization: .words)
                        Picker("Type", selection: $draft.kind) { ForEach(ItemKind.allCases) { Text($0.title).tag($0) } }
                            .pickerStyle(.segmented)
                        GATextField(title: "Country", text: $draft.expected.country, capitalization: .words)
                        HStack(alignment: .top, spacing: 10) {
                            GATextField(title: "Year", text: $yearText, keyboard: .numbersAndPunctuation)
                            GATextField(title: "Mint mark", text: $draft.expected.mint, capitalization: .characters)
                        }
                        GATextField(title: "Denomination", text: $draft.expected.denomination)
                        GATextField(title: "Material", text: $draft.expected.material)
                    }
                    FormCard {
                        VStack(alignment: .leading, spacing: 6) {
                            FieldLabel(title: "Priority")
                            Picker("Priority", selection: $draft.priority) { ForEach(WishPriority.allCases) { Text($0.title).tag($0) } }
                                .pickerStyle(.segmented)
                        }
                        GATextField(title: "Target note", text: $draft.targetNote, prompt: "e.g. up to about 40 USD in VF")
                        Text("A note for yourself — not a price quote or an order.")
                            .font(.caption)
                            .foregroundColor(GAColor.textSecondary)
                        GATextField(title: "Source link", text: $draft.sourceLink, prompt: "https://…", keyboard: .URL, capitalization: .never)
                        GATextArea(title: "Note", text: $draft.note, minHeight: 60)
                    }
                    if let slot = draft.linkedSlot, let set = container.sets.set(id: slot.setID) {
                        InfoNote(text: "Linked to a slot in “\(set.name)”. When you save the acquired item, it is placed in that slot.", symbol: "square.grid.3x3")
                    }
                }
                .padding(GATheme.gutter)
            }
            .gaBackground()
            .navigationTitle(wish == nil ? "Add Wish" : "Edit Wish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.font(.headline) }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func save() {
        errors = []
        if draft.title.isBlank { errors.append("Give the wish a name.") }
        if !yearText.isBlank {
            if let year = Int(yearText.trimmed), year != 0 { draft.expected.year = year } else { errors.append("Year must be a whole number.") }
        } else {
            draft.expected.year = nil
        }
        if !draft.sourceLink.isBlank && WebLink(draft.sourceLink) == nil { errors.append("The source link must start with http:// or https://.") }
        guard errors.isEmpty else { return }
        container.wishUseCase.save(draft)
        dismiss()
    }
}
