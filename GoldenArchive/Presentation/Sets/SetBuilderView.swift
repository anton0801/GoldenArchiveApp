//
//  SetBuilderView.swift
//  GoldenArchive
//
//  Presentation layer — Album / Set Builder. The grid shows real linked
//  items; progress updates after every link or unlink. One record never
//  fills two unique slots without the user confirming its quantity.
//

import SwiftUI

@MainActor
final class SetBuilderViewModel: ArchiveViewModel {
    let setID: UUID
    @Published private(set) var set: CoinSet?
    @Published private(set) var statuses: [SlotStatus] = []
    @Published private(set) var progress: SetProgress = .empty
    @Published private(set) var collectionName: String?
    @Published private(set) var wishedSlotIDs: Set<UUID> = []

    init(container: AppContainer, setID: UUID) {
        self.setID = setID
        super.init(container: container)
        reload()
    }

    override func reload() {
        set = container.sets.set(id: setID)
        guard let set else { return }
        let calculator = SetProgressCalculator(
            coins: container.coins.coins(includeArchived: true),
            sets: container.sets.sets(includeArchived: true),
            groups: container.duplicates.groups()
        )
        statuses = calculator.statuses(for: set)
        progress = calculator.progress(for: set)
        collectionName = set.collectionID.flatMap { container.collections.collection(id: $0)?.name }
        wishedSlotIDs = Set(container.wishes.wishes().filter { $0.status == .wanted }.compactMap { $0.linkedSlot?.setID == setID ? $0.linkedSlot?.slotID : nil })
    }

    func unlink(_ slotID: UUID) { container.linkSlot.unlink(SlotReference(setID: setID, slotID: slotID)) }
    func toggleOptional(_ slotID: UUID) { container.setEditing.toggleOptional(setID: setID, slotID: slotID) }
    func removeSlot(_ slotID: UUID) { container.setEditing.removeSlot(setID: setID, slotID: slotID) }
    func addMissingToWishList() -> Int { container.setEditing.addMissingToWishList(setID: setID) }
    func archive() { container.setEditing.archive(setID: setID, archived: true) }
    func delete() { container.setEditing.delete(setID: setID) }

    func addWish(for slot: SetSlot) {
        guard let set else { return }
        let now = container.clock.now
        container.wishUseCase.save(WishItem(
            title: slot.displayTitle,
            expected: slot.expected,
            linkedSlot: SlotReference(setID: set.id, slotID: slot.id),
            note: "From set “\(set.name)”.",
            createdAt: now,
            updatedAt: now
        ))
    }
}

enum SlotFilter: String, CaseIterable, Identifiable {
    case all, collected, missing, duplicate
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .collected: return "Collected"
        case .missing: return "Missing"
        case .duplicate: return "Duplicate"
        }
    }
}

struct SetBuilderView: View {
    let container: AppContainer
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: SetBuilderViewModel

    @State private var filter: SlotFilter = .all
    @State private var activeSlot: SlotStatus?
    @State private var editingSlot: EditingSlot?
    @State private var linkingSlot: SetSlot?
    @State private var reordering = false
    @State private var editingSet = false
    @State private var savingTemplate = false
    @State private var confirmDelete = false

    struct EditingSlot: Identifiable {
        let id = UUID()
        var slot: SetSlot?
    }

    init(container: AppContainer, setID: UUID) {
        self.container = container
        _model = StateObject(wrappedValue: SetBuilderViewModel(container: container, setID: setID))
    }

    private var filtered: [SlotStatus] {
        switch filter {
        case .all: return model.statuses
        case .collected: return model.statuses.filter { $0.state == .collected }
        case .missing: return model.statuses.filter { $0.state != .collected }
        case .duplicate: return model.statuses.filter(\.isDuplicate)
        }
    }

    var body: some View {
        Group {
            if let set = model.set {
                content(set)
            } else {
                EmptyStateView(title: "Set not found", message: "This set was deleted. Linked items are kept.")
                    .padding(GATheme.gutter)
            }
        }
        .gaBackground()
        .navigationTitle(model.set?.name ?? "Set")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { if model.set != nil { menu } }
        }
        .sheet(item: $activeSlot) { status in
            SlotActionsSheet(
                status: status,
                isWished: model.wishedSlotIDs.contains(status.slot.id),
                onLink: { activeSlot = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { linkingSlot = status.slot } },
                onUnlink: { model.unlink(status.slot.id); activeSlot = nil },
                onAddCoin: {
                    activeSlot = nil
                    router.startAddCoin(AddCoinRequest(
                        collectionID: model.set?.collectionID,
                        prefill: status.slot.expected,
                        prefillName: status.slot.title.isBlank ? nil : status.slot.title,
                        pendingSlot: SlotReference(setID: model.setID, slotID: status.slot.id)
                    ))
                },
                onToggleOptional: { model.toggleOptional(status.slot.id); activeSlot = nil },
                onWish: { model.addWish(for: status.slot); activeSlot = nil; router.show("Added to Wish List", symbol: "star.fill") },
                onEdit: { activeSlot = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { editingSlot = EditingSlot(slot: status.slot) } },
                onRemove: { model.removeSlot(status.slot.id); activeSlot = nil }
            )
            .environmentObject(container)
        }
        .sheet(item: $editingSlot) { item in
            SlotEditorSheet(container: container, setID: model.setID, slot: item.slot)
        }
        .sheet(item: $linkingSlot) { slot in
            LinkCoinSheet(container: container, reference: SlotReference(setID: model.setID, slotID: slot.id), slot: slot)
                .environmentObject(container)
                .environmentObject(router)
        }
        .sheet(isPresented: $reordering) {
            ReorderSlotsSheet(container: container, setID: model.setID)
        }
        .sheet(isPresented: $editingSet) {
            if let set = model.set { SetDetailsEditorSheet(container: container, set: set) }
        }
        .sheet(isPresented: $savingTemplate) {
            SaveTemplateSheet(container: container, setID: model.setID, defaultName: model.set?.name ?? "")
                .environmentObject(router)
        }
        .confirmationDialog("Delete this set?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Set", role: .destructive) {
                model.delete()
                router.show("Set deleted — items kept", symbol: "trash")
                dismiss()
            }
        } message: {
            Text("Only the set and its slots are removed. Linked items stay in your archive.")
        }
    }

    private var menu: some View {
        Menu {
            Button { editingSlot = EditingSlot(slot: nil) } label: { Label("Add Slot", systemImage: "plus.square") }
            Button { reordering = true } label: { Label("Reorder", systemImage: "arrow.up.arrow.down") }
                .disabled(model.statuses.count < 2)
            Button {
                let added = model.addMissingToWishList()
                router.show(added == 0 ? "Every missing slot is already on the Wish List" : "Added \(added) to Wish List", symbol: "star.fill")
            } label: { Label("Add Missing to Wish List", systemImage: "star") }
            Button { savingTemplate = true } label: { Label("Save as Template", systemImage: "square.and.arrow.down") }
            Button { editingSet = true } label: { Label("Edit Set Details", systemImage: "pencil") }
            Divider()
            Button {
                model.archive()
                router.show("Set archived", symbol: "archivebox.fill")
                dismiss()
            } label: { Label("Archive", systemImage: "archivebox") }
            Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis.circle").font(.title3).frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Set actions")
    }

    private func content(_ set: CoinSet) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                NavyPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(model.progress.requiredTotal == 0 ? "—" : model.progress.percentText)
                                .font(.system(size: 40, weight: .heavy, design: .rounded).monospacedDigit())
                                .foregroundColor(GAColor.gold)
                            Text("complete")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(GAColor.silver)
                            Spacer()
                        }
                        GAProgressBar(value: model.progress.fraction, height: 12, onNavy: true)
                        HStack(spacing: 14) {
                            countLabel("\(model.progress.collected)", "Collected", GAColor.success)
                            countLabel("\(model.progress.missing)", "Missing", GAColor.ember)
                            countLabel("\(model.progress.duplicates)", "Duplicate", GAColor.silver)
                        }
                        if let name = model.collectionName {
                            Label(name, systemImage: "folder.fill")
                                .font(.footnote)
                                .foregroundColor(GAColor.silver)
                        }
                        if model.progress.optionalTotal > 0 {
                            Text("\(model.progress.optionalCollected) of \(model.progress.optionalTotal) optional slots filled (not counted in progress)")
                                .font(.caption)
                                .foregroundColor(GAColor.silver)
                        }
                    }
                }

                if !set.note.isBlank {
                    Text(set.note).font(.subheadline).foregroundColor(GAColor.textSecondary)
                }

                GASegmented(options: SlotFilter.allCases, selection: $filter) { $0.title }

                if model.statuses.isEmpty {
                    EmptyStateView(title: "No slots yet", message: "Add a slot for every position you want in this set, then link items you own.", actionTitle: "Add Slot") {
                        editingSlot = EditingSlot(slot: nil)
                    }
                } else if filtered.isEmpty {
                    Text("Nothing in this filter.")
                        .font(.subheadline)
                        .foregroundColor(GAColor.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 16) {
                        ForEach(filtered) { status in
                            Button { activeSlot = status } label: {
                                SlotCell(status: status, isWished: model.wishedSlotIDs.contains(status.slot.id))
                            }
                            .buttonStyle(PressableCardStyle())
                        }
                    }
                }
                Button { editingSlot = EditingSlot(slot: nil) } label: { Label("Add Slot", systemImage: "plus") }
                    .buttonStyle(.ga(.outline, compact: true))
            }
            .padding(GATheme.gutter)
            .padding(.bottom, 24)
        }
    }

    private func countLabel(_ value: String, _ title: String, _ tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(value).font(.subheadline.weight(.heavy).monospacedDigit()).foregroundColor(GAColor.cream)
            Text(title).font(.caption).foregroundColor(GAColor.silver)
        }
        .accessibilityElement(children: .combine)
    }
}

struct SlotCell: View {
    var status: SlotStatus
    var isWished: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if let coin = status.coin {
                    StoredImageView(file: coin.primaryPhoto?.displayFile, maxPixel: 220)
                        .frame(width: 84, height: 84)
                        .clipShape(Circle())
                    Circle().strokeBorder(GAColor.goldRim, lineWidth: 3.5).frame(width: 90, height: 90)
                } else {
                    Circle()
                        .fill(status.state == .optionalMissing ? GAColor.silver.opacity(0.35) : GAColor.navy.opacity(0.08))
                        .frame(width: 88, height: 88)
                    Circle()
                        .strokeBorder(status.state == .optionalMissing ? GAColor.textTertiary : GAColor.navy.opacity(0.45), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                        .frame(width: 88, height: 88)
                    Image(systemName: isWished ? "star.fill" : "plus")
                        .font(.title3.weight(.bold))
                        .foregroundColor(isWished ? GAColor.bronze : GAColor.navy.opacity(0.6))
                }
            }
            .overlay(alignment: .topTrailing) {
                if status.isDuplicate {
                    Text("DUP")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(GAColor.cream)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(GAColor.navy))
                        .accessibilityLabel("Duplicate")
                }
            }
            Text(status.slot.displayTitle)
                .font(.caption.weight(.semibold))
                .foregroundColor(GAColor.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 32, alignment: .top)
            Text(stateText)
                .font(.caption2.weight(.bold))
                .foregroundColor(stateColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(GAColor.card))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(GAColor.stroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var stateText: String {
        switch status.state {
        case .collected: return status.coin?.isArchived == true ? "COLLECTED · ARCHIVED" : "COLLECTED"
        case .missing: return isWished ? "ON WISH LIST" : "MISSING"
        case .optionalMissing: return "OPTIONAL"
        }
    }

    private var stateColor: Color {
        switch status.state {
        case .collected: return GAColor.successText
        case .missing: return GAColor.emberText
        case .optionalMissing: return GAColor.textSecondary
        }
    }
}

// MARK: - Slot sheets

struct SlotActionsSheet: View {
    let status: SlotStatus
    var isWished: Bool
    var onLink: () -> Void
    var onUnlink: () -> Void
    var onAddCoin: () -> Void
    var onToggleOptional: () -> Void
    var onWish: () -> Void
    var onEdit: () -> Void
    var onRemove: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(status.slot.displayTitle)
                        .font(GAFont.title(.title2))
                        .foregroundColor(GAColor.text)
                    if !status.slot.expected.summary.isEmpty {
                        Label("Expected: \(status.slot.expected.summary)", systemImage: "text.magnifyingglass")
                            .font(.subheadline)
                            .foregroundColor(GAColor.textSecondary)
                    }
                    if status.slot.quantityNeeded > 1 {
                        Label("Needs \(status.slot.quantityNeeded) pieces", systemImage: "number")
                            .font(.subheadline)
                            .foregroundColor(GAColor.textSecondary)
                    }
                    if let coin = status.coin {
                        NavigationLink(destination: CoinDetailView(container: container, coinID: coin.id)) {
                            CoinRow(coin: coin).gaCard(padding: 10, radius: 16)
                        }
                        .buttonStyle(.plain)
                        if status.isDuplicate {
                            InfoNote(text: "This record has extra copies or belongs to a duplicate group.", symbol: "square.on.square")
                        }
                        Button("Link a Different Item", action: onLink).buttonStyle(.ga(.outline))
                        Button("Unlink", action: onUnlink).buttonStyle(.ga(.quiet))
                    } else {
                        Button { onLink() } label: { Label("Link Coin", systemImage: "link") }
                            .buttonStyle(.gaPrimary)
                        Button { onAddCoin() } label: { Label("Add a New Item for This Slot", systemImage: "plus.circle") }
                            .buttonStyle(.gaSecondary)
                        if !isWished {
                            Button { onWish() } label: { Label("Add to Wish List", systemImage: "star") }
                                .buttonStyle(.ga(.outline))
                        } else {
                            Label("Already on your Wish List", systemImage: "star.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(GAColor.bronzeText)
                        }
                    }
                    Divider()
                    Button(status.slot.isOptional ? "Mark Required" : "Mark Optional", action: onToggleOptional)
                        .buttonStyle(.ga(.quiet, compact: true))
                    Button("Edit Slot", action: onEdit)
                        .buttonStyle(.ga(.quiet, compact: true))
                    Button("Remove Slot", role: .destructive, action: onRemove)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(GAColor.danger)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(GATheme.gutter)
            }
            .gaBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .navigationViewStyle(.stack)
    }
}

struct SlotEditorSheet: View {
    let container: AppContainer
    let setID: UUID
    let slot: SetSlot?
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var country: String
    @State private var yearText: String
    @State private var denomination: String
    @State private var mint: String
    @State private var material: String
    @State private var isOptional: Bool
    @State private var quantity: Int
    @State private var error: String?

    init(container: AppContainer, setID: UUID, slot: SetSlot?) {
        self.container = container
        self.setID = setID
        self.slot = slot
        _title = State(initialValue: slot?.title ?? "")
        _country = State(initialValue: slot?.expected.country ?? "")
        _yearText = State(initialValue: slot?.expected.year.map { "\($0)" } ?? "")
        _denomination = State(initialValue: slot?.expected.denomination ?? "")
        _mint = State(initialValue: slot?.expected.mint ?? "")
        _material = State(initialValue: slot?.expected.material ?? "")
        _isOptional = State(initialValue: slot?.isOptional ?? false)
        _quantity = State(initialValue: slot?.quantityNeeded ?? 1)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    FormCard {
                        GATextField(title: "Slot title", text: $title, prompt: "e.g. 1921 S", capitalization: .words)
                    }
                    FormCard(title: "Expected attributes", footer: "Used to suggest matching items. At least a title or one attribute is needed.") {
                        GATextField(title: "Country", text: $country, capitalization: .words)
                        HStack(alignment: .top, spacing: 10) {
                            GATextField(title: "Year", text: $yearText, keyboard: .numbersAndPunctuation, error: error)
                            GATextField(title: "Mint mark", text: $mint, capitalization: .characters)
                        }
                        GATextField(title: "Denomination", text: $denomination)
                        GATextField(title: "Material", text: $material)
                    }
                    FormCard {
                        GAToggleRow(title: "Optional slot", subtitle: "Optional slots are not counted in progress.", isOn: $isOptional)
                        QuantityStepper(title: "Pieces needed", value: $quantity, range: 1...99)
                    }
                }
                .padding(GATheme.gutter)
            }
            .gaBackground()
            .navigationTitle(slot == nil ? "Add Slot" : "Edit Slot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.font(.headline) }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func save() {
        var year: Int?
        if !yearText.isBlank {
            guard let value = Int(yearText.trimmed), value != 0, abs(value) <= 3000 else {
                error = "Year must be a whole number (negative for BC)."
                return
            }
            year = value
        }
        let expected = ExpectedAttributes(country: country.trimmed, year: year, denomination: denomination.trimmed, mint: mint.trimmed, material: material.trimmed)
        guard !title.isBlank || !expected.isEmpty else {
            error = "Add a title or at least one attribute."
            return
        }
        if var existing = slot {
            existing.title = title.trimmed
            existing.expected = expected
            existing.isOptional = isOptional
            existing.quantityNeeded = quantity
            container.setEditing.updateSlot(setID: setID, slot: existing)
        } else {
            container.setEditing.addSlot(setID: setID, slot: SetSlot(title: title.trimmed, expected: expected, isOptional: isOptional, quantityNeeded: quantity))
        }
        dismiss()
    }
}

/// Picks an item for a slot; best metadata matches first.
struct LinkCoinSheet: View {
    let container: AppContainer
    let reference: SlotReference
    let slot: SetSlot
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: AppRouter
    @State private var search = ""
    @State private var confirmation: QuantityConfirmation?

    struct QuantityConfirmation: Identifiable {
        let id = UUID()
        var coin: Coin
        var current: Int
        var required: Int
        var otherSlots: [String]
    }

    private var candidates: [(coin: Coin, match: (matched: Int, total: Int))] {
        let query = search.normalizedKey
        return container.coins.coins(includeArchived: false)
            .filter { query.isEmpty || $0.searchText.contains(query) }
            .map { ($0, SlotMatcher.match($0, slot.expected)) }
            .sorted { lhs, rhs in
                lhs.match.matched == rhs.match.matched
                    ? lhs.coin.displayName.localizedCaseInsensitiveCompare(rhs.coin.displayName) == .orderedAscending
                    : lhs.match.matched > rhs.match.matched
            }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if !slot.expected.summary.isEmpty {
                        InfoNote(text: "Slot expects: \(slot.expected.summary)", symbol: "text.magnifyingglass")
                    }
                    if candidates.isEmpty {
                        EmptyStateView(title: "No items to link", message: "Add the item to your archive first, then link it here.")
                    }
                    ForEach(candidates, id: \.coin.id) { candidate in
                        Button { link(candidate.coin, confirm: false) } label: {
                            CoinRow(coin: candidate.coin, trailing: candidate.match.total > 0 ? "\(candidate.match.matched)/\(candidate.match.total)" : nil, showsChevron: false)
                                .gaCard(padding: 10, radius: 16)
                        }
                        .buttonStyle(PressableCardStyle())
                        .accessibilityHint(candidate.match.total > 0 ? "Matches \(candidate.match.matched) of \(candidate.match.total) expected attributes" : "")
                    }
                }
                .padding(GATheme.gutter)
            }
            .gaBackground()
            .searchable(text: $search, prompt: "Search your items")
            .navigationTitle("Link Coin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .alert(item: $confirmation) { item in
                Alert(
                    title: Text("Confirm quantity"),
                    message: Text("“\(item.coin.displayName)” has quantity \(item.current) and already fills: \(item.otherSlots.joined(separator: "; ")). To fill this slot too, you need \(item.required) pieces. Do you own \(item.required)?"),
                    primaryButton: .default(Text("Yes, set quantity to \(item.required)")) { link(item.coin, confirm: true) },
                    secondaryButton: .cancel()
                )
            }
        }
        .navigationViewStyle(.stack)
    }

    private func link(_ coin: Coin, confirm: Bool) {
        let result = container.linkSlot.execute(coinID: coin.id, slot: reference, confirmQuantity: confirm)
        switch result {
        case .linked, .alreadyLinked:
            router.show("Linked to \(slot.displayTitle)", symbol: "link")
            dismiss()
        case .needsQuantityConfirmation(let current, let required, let others):
            confirmation = QuantityConfirmation(coin: coin, current: current, required: required, otherSlots: others)
        case .notFound:
            dismiss()
        }
    }
}

/// From Coin Details: place an item into a set slot.
struct AddToSetSheet: View {
    let container: AppContainer
    let coinID: UUID
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: AppRouter
    @State private var selectedSetID: UUID?
    @State private var confirmation: (slot: SlotReference, current: Int, required: Int)?
    @State private var showConfirmation = false
    @State private var creatingSet = false

    private var coin: Coin? { container.coins.coin(id: coinID) }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    let sets = container.sets.sets(includeArchived: false)
                    if sets.isEmpty {
                        EmptyStateView(title: "No sets yet", message: "Create a set first, then place this item in one of its slots.", actionTitle: "Create Set") { creatingSet = true }
                    }
                    ForEach(sets) { set in
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                withAnimation { selectedSetID = selectedSetID == set.id ? nil : set.id }
                            } label: {
                                HStack {
                                    Text(set.name).font(.headline).foregroundColor(GAColor.text)
                                    Spacer()
                                    Text("\(set.slots.filter { $0.linkedCoinID == nil }.count) empty")
                                        .font(.caption)
                                        .foregroundColor(GAColor.textSecondary)
                                    Image(systemName: selectedSetID == set.id ? "chevron.up" : "chevron.down")
                                        .foregroundColor(GAColor.textSecondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if selectedSetID == set.id { slotList(set) }
                        }
                        .gaCard(padding: 12, radius: 16)
                    }
                }
                .padding(GATheme.gutter)
            }
            .gaBackground()
            .navigationTitle("Add to Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .alert("Confirm quantity", isPresented: $showConfirmation, presenting: confirmation) { item in
                Button("Yes, set quantity to \(item.required)") { link(item.slot, confirm: true) }
                Button("Cancel", role: .cancel) {}
            } message: { item in
                Text("This record has quantity \(item.current). Filling this slot as well needs \(item.required) physical pieces. One record cannot fill two unique slots unless you own enough pieces.")
            }
            .sheet(isPresented: $creatingSet) {
                NewSetSheet(container: container, presetCollectionID: coin?.collectionID).environmentObject(router)
            }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private func slotList(_ set: CoinSet) -> some View {
        let empty = set.slots.filter { $0.linkedCoinID == nil }
        let sorted = coin.map { c in empty.sorted { SlotMatcher.match(c, $0.expected).matched > SlotMatcher.match(c, $1.expected).matched } } ?? empty
        ForEach(sorted) { slot in
            Button { link(SlotReference(setID: set.id, slotID: slot.id), confirm: false) } label: {
                HStack {
                    Image(systemName: "circle.dashed").foregroundColor(GAColor.navy)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(slot.displayTitle).font(.subheadline.weight(.semibold)).foregroundColor(GAColor.text)
                        if let coin, !slot.expected.isEmpty {
                            let match = SlotMatcher.match(coin, slot.expected)
                            Text("Matches \(match.matched) of \(match.total) expected attributes")
                                .font(.caption)
                                .foregroundColor(GAColor.textSecondary)
                        }
                    }
                    Spacer()
                    Text("Link").font(.footnote.weight(.bold)).foregroundColor(GAColor.bronzeText)
                }
                .frame(minHeight: 40)
            }
            .buttonStyle(.plain)
        }
        Button {
            guard let coin else { return }
            let slot = SetSlot(title: coin.displayName, expected: coin.attributes)
            container.setEditing.addSlot(setID: set.id, slot: slot)
            link(SlotReference(setID: set.id, slotID: slot.id), confirm: false)
        } label: {
            Label("Add as a new slot", systemImage: "plus")
                .font(.footnote.weight(.bold))
                .foregroundColor(GAColor.bronzeText)
                .frame(minHeight: 40)
        }
    }

    private func link(_ reference: SlotReference, confirm: Bool) {
        switch container.linkSlot.execute(coinID: coinID, slot: reference, confirmQuantity: confirm) {
        case .linked, .alreadyLinked:
            router.show("Placed in set", symbol: "link")
            dismiss()
        case .needsQuantityConfirmation(let current, let required, _):
            confirmation = (reference, current, required)
            showConfirmation = true
        case .notFound:
            break
        }
    }
}

struct ReorderSlotsSheet: View {
    let container: AppContainer
    let setID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var slots: [SetSlot] = []

    var body: some View {
        NavigationView {
            List {
                ForEach(slots) { slot in
                    HStack {
                        Image(systemName: slot.linkedCoinID == nil ? "circle.dashed" : "checkmark.circle.fill")
                            .foregroundColor(slot.linkedCoinID == nil ? GAColor.textTertiary : GAColor.success)
                        Text(slot.displayTitle)
                    }
                }
                .onMove { slots.move(fromOffsets: $0, toOffset: $1) }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder Slots")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if var set = container.sets.set(id: setID) {
                            set.slots = slots
                            container.setEditing.update(set)
                        }
                        dismiss()
                    }
                    .font(.headline)
                }
            }
            .onAppear { slots = container.sets.set(id: setID)?.slots ?? [] }
        }
        .navigationViewStyle(.stack)
    }
}

struct SetDetailsEditorSheet: View {
    let container: AppContainer
    let set: CoinSet
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var collectionID: UUID?
    @State private var note: String

    init(container: AppContainer, set: CoinSet) {
        self.container = container
        self.set = set
        _name = State(initialValue: set.name)
        _collectionID = State(initialValue: set.collectionID)
        _note = State(initialValue: set.note)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                FormCard {
                    GATextField(title: "Set name", text: $name, required: true, capitalization: .words, error: name.isBlank ? "Name is required." : nil)
                    GAMenuPicker(title: "Collection", selection: $collectionID,
                                 options: [(nil, "None")] + container.collections.collections(includeArchived: false).map { (Optional($0.id), $0.name) })
                    GATextArea(title: "Note", text: $note, minHeight: 60)
                }
                .padding(GATheme.gutter)
            }
            .gaBackground()
            .navigationTitle("Set Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var copy = set
                        copy.name = name.trimmed
                        copy.collectionID = collectionID
                        copy.note = note.trimmed
                        container.setEditing.update(copy)
                        dismiss()
                    }
                    .font(.headline)
                    .disabled(name.isBlank)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

struct SaveTemplateSheet: View {
    let container: AppContainer
    let setID: UUID
    let defaultName: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: AppRouter
    @State private var name = ""

    var body: some View {
        NavigationView {
            ScrollView {
                FormCard(footer: "The template keeps slot titles, expected attributes and optional flags — never the linked items.") {
                    GATextField(title: "Template name", text: $name, prompt: defaultName, capitalization: .words)
                }
                .padding(GATheme.gutter)
            }
            .gaBackground()
            .navigationTitle("Save as Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        container.setEditing.saveAsTemplate(setID: setID, name: name)
                        router.show("Template saved", symbol: "square.and.arrow.down.fill")
                        dismiss()
                    }
                    .font(.headline)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
