//
//  CollectionDetailView.swift
//  GoldenArchive
//

import SwiftUI

@MainActor
final class CollectionDetailViewModel: ArchiveViewModel {
    let collectionID: UUID
    @Published private(set) var collection: CoinCollection?
    @Published private(set) var items: [Coin] = []
    @Published private(set) var sets: [SetSummary] = []
    @Published private(set) var coverFile: StoredFile?

    init(container: AppContainer, collectionID: UUID) {
        self.collectionID = collectionID
        super.init(container: container)
        reload()
    }

    override func reload() {
        collection = container.collections.collection(id: collectionID)
        guard let collection else { return }
        let members = container.coins.coins(includeArchived: false).filter { $0.collectionID == collectionID }
        items = CollectionUseCase.sorted(members, by: collection.itemSort)
        coverFile = CollectionsViewModel.coverFile(for: collection, members: members)
        let allCoins = container.coins.coins(includeArchived: true)
        let calculator = SetProgressCalculator(coins: allCoins, sets: container.sets.sets(includeArchived: true), groups: container.duplicates.groups())
        sets = container.sets.sets(includeArchived: false)
            .filter { $0.collectionID == collectionID }
            .map { SetSummary(set: $0, progress: calculator.progress(for: $0)) }
    }

    var pieceCount: Int { items.reduce(0) { $0 + $1.quantity } }

    func setItemSort(_ sort: ItemSortOrder) {
        guard var collection else { return }
        collection.itemSort = sort
        container.collectionUseCase.update(collection)
    }

    func duplicateStructure() -> CoinCollection? { container.collectionUseCase.duplicateStructure(id: collectionID) }
    func archive() { container.collectionUseCase.archive(id: collectionID, archived: true) }
    func delete(_ choice: CollectionDeletionChoice) { container.collectionUseCase.delete(id: collectionID, choice: choice) }
}

struct CollectionDetailView: View {
    let container: AppContainer
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: CollectionDetailViewModel

    @State private var editing = false
    @State private var choosingCover = false
    @State private var moving = false
    @State private var deleting = false
    @State private var confirmArchive = false
    @State private var newSet = false

    init(container: AppContainer, collectionID: UUID) {
        self.container = container
        _model = StateObject(wrappedValue: CollectionDetailViewModel(container: container, collectionID: collectionID))
    }

    var body: some View {
        Group {
            if let collection = model.collection {
                content(collection)
            } else {
                EmptyStateView(title: "Collection not found", message: "It was deleted. Its items are kept.")
                    .padding(GATheme.gutter)
            }
        }
        .gaBackground()
        .navigationTitle(model.collection?.name ?? "Collection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if model.collection != nil { menu }
            }
        }
        .sheet(isPresented: $editing) {
            CollectionEditorSheet(container: container, collection: model.collection) { _ in }
                .environmentObject(router)
        }
        .sheet(isPresented: $choosingCover) {
            ChooseCoverSheet(container: container, collectionID: model.collectionID)
        }
        .sheet(isPresented: $moving) {
            MoveItemsSheet(container: container, coinIDs: model.items.map(\.id), currentCollectionID: model.collectionID)
        }
        .sheet(isPresented: $deleting) {
            DeleteCollectionSheet(container: container, collectionID: model.collectionID) { choice in
                model.delete(choice)
                router.show("Collection deleted — items kept", symbol: "folder.badge.minus")
                dismiss()
            }
        }
        .sheet(isPresented: $newSet) {
            NewSetSheet(container: container, presetCollectionID: model.collectionID)
                .environmentObject(router)
        }
        .confirmationDialog("Archive this collection?", isPresented: $confirmArchive, titleVisibility: .visible) {
            Button("Archive Collection") {
                model.archive()
                router.show("Collection archived", symbol: "archivebox.fill")
                dismiss()
            }
        } message: {
            Text("It is hidden from lists. Items stay where they are and can still be found in All Items.")
        }
    }

    private var menu: some View {
        Menu {
            Button { editing = true } label: { Label("Rename & Edit", systemImage: "pencil") }
            Button { choosingCover = true } label: { Label("Choose Cover", systemImage: "photo") }
            Button { moving = true } label: { Label("Move Items", systemImage: "folder") }
                .disabled(model.items.isEmpty)
            Button {
                if let copy = model.duplicateStructure() { router.show("Created “\(copy.name)”", symbol: "square.on.square") }
            } label: { Label("Duplicate Structure", systemImage: "square.on.square.dashed") }
            Divider()
            Button { confirmArchive = true } label: { Label("Archive", systemImage: "archivebox") }
            Button(role: .destructive) { deleting = true } label: { Label("Delete", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis.circle").font(.title3).frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Collection actions")
    }

    private func content(_ collection: CoinCollection) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                NavyPanel {
                    HStack(spacing: 14) {
                        Group {
                            if model.coverFile != nil {
                                StoredImageView(file: model.coverFile, maxPixel: 240)
                            } else {
                                ZStack {
                                    Color.white.opacity(0.08)
                                    Image(systemName: collection.theme.symbolName).font(.title).foregroundColor(GAColor.gold)
                                }
                            }
                        }
                        .frame(width: 92, height: 92)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(GAColor.gold, lineWidth: 2))
                        .onTapGesture { choosingCover = true }
                        .accessibilityLabel("Cover. Double-tap to choose.")

                        VStack(alignment: .leading, spacing: 4) {
                            Text(collection.theme.title.uppercased())
                                .font(.caption.weight(.heavy))
                                .tracking(1)
                                .foregroundColor(GAColor.gold)
                            Text("\(model.pieceCount)")
                                .font(.system(size: 38, weight: .heavy, design: .rounded).monospacedDigit())
                                .foregroundColor(GAColor.cream)
                            Text("\(GAFormat.count(model.items.count, "record")) · \(GAFormat.count(model.sets.count, "set"))")
                                .font(.footnote)
                                .foregroundColor(GAColor.silver)
                        }
                    }
                }

                if !collection.completionNote.isBlank || !collection.tags.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        if !collection.completionNote.isBlank {
                            Label(collection.completionNote, systemImage: "flag.checkered")
                                .font(.subheadline)
                                .foregroundColor(GAColor.text)
                        }
                        if !collection.tags.isEmpty { TagChipsView(tags: collection.tags) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .gaCard()
                }

                HStack(spacing: 10) {
                    Button {
                        router.startAddCoin(AddCoinRequest(collectionID: collection.id))
                    } label: { Label("Add Coin", systemImage: "plus") }
                    .buttonStyle(.ga(.primary, compact: true))
                    Button { newSet = true } label: { Label("New Set", systemImage: "square.grid.3x3") }
                        .buttonStyle(.ga(.outline, compact: true))
                }

                if !model.sets.isEmpty {
                    SectionHeader(title: "Sets")
                    ForEach(model.sets) { item in
                        NavigationLink(destination: SetBuilderView(container: container, setID: item.set.id)) {
                            SetProgressCard(name: item.set.name, progress: item.progress)
                        }
                        .buttonStyle(PressableCardStyle())
                    }
                }

                HStack {
                    SectionHeader(title: "Items")
                    Menu {
                        Picker("Sort", selection: Binding(get: { collection.itemSort }, set: { model.setItemSort($0) })) {
                            ForEach(ItemSortOrder.allCases) { Text($0.title).tag($0) }
                        }
                    } label: {
                        Label(collection.itemSort.title, systemImage: "arrow.up.arrow.down")
                            .font(.footnote.weight(.bold))
                            .foregroundColor(GAColor.bronzeText)
                    }
                }
                if model.items.isEmpty {
                    EmptyStateView(title: "No items yet", message: "Add a coin to this collection, or move items here from another collection.")
                } else {
                    ForEach(model.items) { coin in
                        NavigationLink(destination: CoinDetailView(container: container, coinID: coin.id)) {
                            CoinRow(coin: coin).gaCard(padding: 10, radius: 16)
                        }
                        .buttonStyle(PressableCardStyle())
                    }
                    NavigationLink(destination: ItemListView(container: container, scope: .collection(collection.id))) {
                        Text("Search & select items")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(GAColor.bronzeText)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            }
            .padding(GATheme.gutter)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Sheets

struct CollectionEditorSheet: View {
    let container: AppContainer
    let collection: CoinCollection?
    var onDone: (CoinCollection?) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: AppRouter

    @State private var name: String
    @State private var theme: CollectionTheme
    @State private var tags: [String]
    @State private var note: String
    @State private var showError = false

    init(container: AppContainer, collection: CoinCollection?, onDone: @escaping (CoinCollection?) -> Void) {
        self.container = container
        self.collection = collection
        self.onDone = onDone
        _name = State(initialValue: collection?.name ?? "")
        _theme = State(initialValue: collection?.theme ?? .country)
        _tags = State(initialValue: collection?.tags ?? [])
        _note = State(initialValue: collection?.completionNote ?? "")
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    FormCard {
                        GATextField(title: "Collection name", text: $name, prompt: "e.g. Victorian silver", required: true, capitalization: .words,
                                    error: showError ? "Give the collection a name." : nil)
                        VStack(alignment: .leading, spacing: 8) {
                            FieldLabel(title: "Theme")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(CollectionTheme.allCases) { item in
                                        ChoiceChip(title: item.title, isSelected: theme == item, symbol: item.symbolName) { theme = item }
                                    }
                                }
                            }
                        }
                        GATextField(title: "Completion note", text: $note, prompt: "e.g. missing the 1916 and 1921 issues")
                        TagEditor(tags: $tags)
                    }
                }
                .padding(GATheme.gutter)
            }
            .gaBackground()
            .navigationTitle(collection == nil ? "New Collection" : "Edit Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(collection == nil ? "Create" : "Save") { save() }.font(.headline) }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func save() {
        guard !name.isBlank else {
            showError = true
            return
        }
        if var existing = collection {
            existing.name = name
            existing.theme = theme
            existing.tags = tags
            existing.completionNote = note.trimmed
            container.collectionUseCase.update(existing)
            onDone(existing)
        } else {
            let created = container.collectionUseCase.create(name: name, theme: theme, tags: tags, completionNote: note)
            router.show("Collection created")
            onDone(created)
        }
        dismiss()
    }
}

struct MoveItemsSheet: View {
    let container: AppContainer
    let coinIDs: [UUID]
    let currentCollectionID: UUID?
    var onDone: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var destination: UUID??

    var body: some View {
        NavigationView {
            List {
                Section(footer: Text("Only the collection changes. Photos, documents and set slots stay with each item.")) {
                    destinationRow(nil, "Unsorted", "tray")
                    ForEach(container.collections.collections(includeArchived: false)) { collection in
                        destinationRow(collection.id, collection.name, collection.theme.symbolName)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Move \(GAFormat.count(coinIDs.count, "item"))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") {
                        guard let target = destination else { return }
                        let name = target.flatMap { container.collections.collection(id: $0)?.name } ?? "Unsorted"
                        container.coinState.move(coinIDs: coinIDs, to: target, collectionName: name)
                        onDone?()
                        dismiss()
                    }
                    .font(.headline)
                    .disabled(destination == nil)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func destinationRow(_ id: UUID?, _ title: String, _ symbol: String) -> some View {
        Button {
            destination = .some(id)
        } label: {
            HStack {
                Image(systemName: symbol).foregroundColor(GAColor.bronzeText).frame(width: 26)
                Text(title).foregroundColor(GAColor.text)
                if id == currentCollectionID && coinIDs.count == 1 {
                    Text("current").font(.caption).foregroundColor(GAColor.textSecondary)
                }
                Spacer()
                if destination == .some(id) {
                    Image(systemName: "checkmark").foregroundColor(GAColor.success)
                }
            }
            .frame(minHeight: 36)
        }
    }
}

struct ChooseCoverSheet: View {
    let container: AppContainer
    let collectionID: UUID
    @Environment(\.dismiss) private var dismiss

    private var options: [(coin: Coin, photo: CoinPhoto)] {
        container.coins.coins(includeArchived: false)
            .filter { $0.collectionID == collectionID }
            .flatMap { coin in coin.sortedPhotos.map { (coin, $0) } }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                if options.isEmpty {
                    EmptyStateView(title: "No photos in this collection", message: "Add photos to its items first. The cover always uses your own photos.")
                        .padding(GATheme.gutter)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                        ForEach(options, id: \.photo.id) { option in
                            Button {
                                container.collectionUseCase.setCover(id: collectionID, cover: CoverReference(coinID: option.coin.id, photoID: option.photo.id))
                                dismiss()
                            } label: {
                                StoredImageView(file: option.photo.displayFile, maxPixel: 220)
                                    .frame(height: 100)
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .accessibilityLabel("\(option.coin.displayName), \(option.photo.side.title)")
                        }
                    }
                    .padding(GATheme.gutter)
                }
            }
            .gaBackground()
            .navigationTitle("Choose Cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Automatic") {
                        container.collectionUseCase.setCover(id: collectionID, cover: nil)
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

struct DeleteCollectionSheet: View {
    let container: AppContainer
    let collectionID: UUID
    var onDelete: (CollectionDeletionChoice) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var keepUnsorted = true
    @State private var target: UUID?

    var body: some View {
        let collection = container.collections.collection(id: collectionID)
        let others = container.collections.collections(includeArchived: false).filter { $0.id != collectionID }
        let count = container.collectionUseCase.itemCount(collectionID: collectionID)
        return NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Delete “\(collection?.name ?? "")”?")
                        .font(GAFont.title(.title2))
                        .foregroundColor(GAColor.text)
                    Text("\(GAFormat.count(count, "item")) and its sets are kept. Choose where the items go:")
                        .font(.subheadline)
                        .foregroundColor(GAColor.textSecondary)
                    VStack(spacing: 10) {
                        choiceRow(title: "Keep Unsorted", subtitle: "Items stay in the archive without a collection.", selected: keepUnsorted) {
                            keepUnsorted = true
                        }
                        choiceRow(title: "Move Items", subtitle: others.isEmpty ? "No other collection yet." : "Move them into another collection.", selected: !keepUnsorted) {
                            if !others.isEmpty { keepUnsorted = false }
                        }
                        if !keepUnsorted {
                            GAMenuPicker(title: "Destination", selection: $target, options: [(nil, "Choose…")] + others.map { (Optional($0.id), $0.name) })
                        }
                    }
                    .gaCard()
                    Button("Delete Collection") {
                        if keepUnsorted { onDelete(.keepUnsorted) } else if let target { onDelete(.moveItems(to: target)) }
                    }
                    .buttonStyle(.gaDestructive)
                    .disabled(!keepUnsorted && target == nil)
                }
                .padding(GATheme.gutter)
            }
            .gaBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .navigationViewStyle(.stack)
    }

    private func choiceRow(title: String, subtitle: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(selected ? GAColor.navy : GAColor.textTertiary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundColor(GAColor.text)
                    Text(subtitle).font(.footnote).foregroundColor(GAColor.textSecondary)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

struct ReorderCollectionsSheet: View {
    let container: AppContainer
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var items: [CoinCollection] = []

    var body: some View {
        NavigationView {
            List {
                ForEach(items) { item in
                    Label(item.name, systemImage: item.theme.symbolName)
                }
                .onMove { source, destination in items.move(fromOffsets: source, toOffset: destination) }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        container.collectionUseCase.reorder(items)
                        onDone()
                        dismiss()
                    }
                    .font(.headline)
                }
            }
            .onAppear {
                items = container.collections.collections(includeArchived: false).sorted { $0.sortIndex < $1.sortIndex }
            }
        }
        .navigationViewStyle(.stack)
    }
}
