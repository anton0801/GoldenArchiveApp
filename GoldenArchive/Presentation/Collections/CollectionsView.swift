//
//  CollectionsView.swift
//  GoldenArchive
//
//  Presentation layer — themed collections. Deleting a collection offers
//  Move Items or Keep Unsorted; items themselves are never deleted here.
//

import SwiftUI

struct CollectionSummary: Identifiable, Hashable {
    var collection: CoinCollection
    var itemCount: Int
    var coverFile: StoredFile?
    var setCount: Int
    var id: UUID { collection.id }
}

@MainActor
final class CollectionsViewModel: ArchiveViewModel {
    @Published private(set) var summaries: [CollectionSummary] = []
    @Published private(set) var allCount = 0
    @Published private(set) var unsortedCount = 0
    @Published var sort: CollectionListSort

    override init(container: AppContainer) {
        sort = container.settings.settings().collectionListSort
        super.init(container: container)
        reload()
    }

    override func reload() {
        let coins = container.coins.coins(includeArchived: false)
        let sets = container.sets.sets(includeArchived: false)
        allCount = coins.count
        unsortedCount = coins.filter { $0.collectionID == nil }.count
        let items = container.collections.collections(includeArchived: false).map { collection -> CollectionSummary in
            let members = coins.filter { $0.collectionID == collection.id }
            return CollectionSummary(
                collection: collection,
                itemCount: members.reduce(0) { $0 + $1.quantity },
                coverFile: CollectionsViewModel.coverFile(for: collection, members: members),
                setCount: sets.filter { $0.collectionID == collection.id }.count
            )
        }
        summaries = sorted(items)
    }

    static func coverFile(for collection: CoinCollection, members: [Coin]) -> StoredFile? {
        if let cover = collection.cover,
           let coin = members.first(where: { $0.id == cover.coinID }),
           let photo = coin.photos.first(where: { $0.id == cover.photoID }) {
            return photo.displayFile
        }
        return members.sorted { $0.createdAt > $1.createdAt }.first { $0.primaryPhoto != nil }?.primaryPhoto?.displayFile
    }

    private func sorted(_ items: [CollectionSummary]) -> [CollectionSummary] {
        switch sort {
        case .manual: return items.sorted { $0.collection.sortIndex < $1.collection.sortIndex }
        case .name: return items.sorted { $0.collection.name.localizedCaseInsensitiveCompare($1.collection.name) == .orderedAscending }
        case .itemCount: return items.sorted { $0.itemCount > $1.itemCount }
        case .recent: return items.sorted { $0.collection.updatedAt > $1.collection.updatedAt }
        }
    }

    func setSort(_ value: CollectionListSort) {
        sort = value
        container.settings.update { $0.collectionListSort = value }
        reload()
    }
}

struct CollectionsView: View {
    let container: AppContainer
    var isRoot = true
    @EnvironmentObject private var router: AppRouter
    @StateObject private var model: CollectionsViewModel
    @State private var creating = false
    @State private var reordering = false

    init(container: AppContainer, isRoot: Bool = true) {
        self.container = container
        self.isRoot = isRoot
        _model = StateObject(wrappedValue: CollectionsViewModel(container: container))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    NavigationLink(destination: ItemListView(container: container, scope: .all)) {
                        smallTile("All Items", "\(model.allCount)", "tray.full.fill")
                    }
                    .buttonStyle(PressableCardStyle())
                    NavigationLink(destination: ItemListView(container: container, scope: .unsorted)) {
                        smallTile("Unsorted", "\(model.unsortedCount)", "tray.fill")
                    }
                    .buttonStyle(PressableCardStyle())
                }

                if model.summaries.isEmpty {
                    EmptyStateView(
                        artwork: .album,
                        artSize: CGSize(width: 180, height: 140),
                        title: "No collections yet",
                        message: "Group items by country, era, material or any theme you like. Items can live in one collection or stay Unsorted.",
                        actionTitle: "Create Collection",
                        action: { creating = true }
                    )
                } else {
                    SectionHeader(title: "Collections", subtitle: model.sort.title)
                    ForEach(model.summaries) { summary in
                        NavigationLink(destination: CollectionDetailView(container: container, collectionID: summary.id)) {
                            CollectionCard(summary: summary)
                        }
                        .buttonStyle(PressableCardStyle())
                    }
                }
            }
            .padding(GATheme.gutter)
            .padding(.bottom, 24)
        }
        .gaBackground()
        .navigationTitle("Collections")
        .navigationBarTitleDisplayMode(isRoot ? .large : .inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu {
                    Picker("Sort", selection: Binding(get: { model.sort }, set: { model.setSort($0) })) {
                        ForEach(CollectionListSort.allCases) { Text($0.title).tag($0) }
                    }
                    if model.summaries.count > 1 {
                        Button { reordering = true } label: { Label("Reorder…", systemImage: "arrow.up.arrow.down") }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Sort order")
                Button { creating = true } label: {
                    Image(systemName: "plus.circle.fill").font(.title3).frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Create collection")
            }
        }
        .sheet(isPresented: $creating) {
            CollectionEditorSheet(container: container, collection: nil) { _ in }
                .environmentObject(router)
        }
        .sheet(isPresented: $reordering) {
            ReorderCollectionsSheet(container: container, onDone: { model.setSort(.manual) })
        }
    }

    private func smallTile(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack(spacing: 10) {
            IconBadge(symbol: symbol, tint: GAColor.navy, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(GAFont.number(.headline)).foregroundColor(GAColor.text)
                Text(title).font(.caption.weight(.semibold)).foregroundColor(GAColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .gaCard(padding: 12, radius: 16)
    }
}

struct CollectionCard: View {
    var summary: CollectionSummary

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                if summary.coverFile != nil {
                    StoredImageView(file: summary.coverFile, maxPixel: 200)
                } else {
                    ZStack {
                        GAColor.navyFill
                        Image(systemName: summary.collection.theme.symbolName)
                            .font(.title2)
                            .foregroundColor(GAColor.gold)
                    }
                }
            }
            .frame(width: 78, height: 78)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(GAColor.gold.opacity(0.6), lineWidth: 1.5))

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.collection.name)
                    .font(.headline)
                    .foregroundColor(GAColor.text)
                    .lineLimit(2)
                Text("\(GAFormat.count(summary.itemCount, "item")) · \(summary.collection.theme.title)\(summary.setCount > 0 ? " · \(GAFormat.count(summary.setCount, "set"))" : "")")
                    .font(.footnote)
                    .foregroundColor(GAColor.textSecondary)
                if !summary.collection.completionNote.isBlank {
                    Text(summary.collection.completionNote)
                        .font(.caption)
                        .foregroundColor(GAColor.bronzeText)
                        .lineLimit(2)
                }
                if !summary.collection.tags.isEmpty {
                    Text(summary.collection.tags.map { "#\($0)" }.joined(separator: " "))
                        .font(.caption)
                        .foregroundColor(GAColor.navy)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundColor(GAColor.textTertiary)
        }
        .gaCard(padding: 12)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Items list

enum ItemListScope: Hashable {
    case all
    case unsorted
    case collection(UUID)
    case ids([UUID], title: String)
}

@MainActor
final class ItemListViewModel: ArchiveViewModel {
    let scope: ItemListScope
    @Published var searchText = "" { didSet { reload() } }
    @Published var kindFilter: ItemKind? { didSet { reload() } }
    @Published var sort: ItemSortOrder = .recent { didSet { reload() } }
    @Published private(set) var items: [Coin] = []

    init(container: AppContainer, scope: ItemListScope) {
        self.scope = scope
        super.init(container: container)
        if case .collection(let id) = scope { sort = container.collections.collection(id: id)?.itemSort ?? .recent }
        reload()
    }

    override func reload() {
        var coins = container.coins.coins(includeArchived: false)
        switch scope {
        case .all: break
        case .unsorted: coins = coins.filter { $0.collectionID == nil }
        case .collection(let id): coins = coins.filter { $0.collectionID == id }
        case .ids(let ids, _):
            let set = Set(ids)
            coins = container.coins.coins(includeArchived: true).filter { set.contains($0.id) }
        }
        if let kindFilter { coins = coins.filter { $0.kind == kindFilter } }
        let query = searchText.normalizedKey
        if !query.isEmpty { coins = coins.filter { $0.searchText.contains(query) } }
        items = CollectionUseCase.sorted(coins, by: sort)
    }

    var title: String {
        switch scope {
        case .all: return "All Items"
        case .unsorted: return "Unsorted"
        case .collection(let id): return container.collections.collection(id: id)?.name ?? "Collection"
        case .ids(_, let title): return title
        }
    }
}

struct ItemListView: View {
    let container: AppContainer
    @StateObject private var model: ItemListViewModel
    @State private var selecting = false
    @State private var selection = Set<UUID>()
    @State private var moving = false

    init(container: AppContainer, scope: ItemListScope) {
        self.container = container
        _model = StateObject(wrappedValue: ItemListViewModel(container: container, scope: scope))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ChoiceChip(title: "All", isSelected: model.kindFilter == nil) { model.kindFilter = nil }
                        ForEach(ItemKind.allCases) { kind in
                            ChoiceChip(title: kind.pluralTitle, isSelected: model.kindFilter == kind) { model.kindFilter = kind }
                        }
                    }
                }
                if model.items.isEmpty {
                    EmptyStateView(title: model.searchText.isEmpty ? "No items here" : "No matches", message: model.searchText.isEmpty ? "Items you add will be listed here." : "Try a different word — search looks at names, countries, years, materials, notes and tags.")
                } else {
                    Text(GAFormat.count(model.items.count, "record"))
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(GAColor.textSecondary)
                    ForEach(model.items) { coin in
                        if selecting {
                            Button { toggle(coin.id) } label: {
                                HStack {
                                    Image(systemName: selection.contains(coin.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundColor(selection.contains(coin.id) ? GAColor.success : GAColor.textTertiary)
                                    CoinRow(coin: coin, showsChevron: false)
                                }
                                .gaCard(padding: 10, radius: 16)
                            }
                            .buttonStyle(.plain)
                        } else {
                            NavigationLink(destination: CoinDetailView(container: container, coinID: coin.id)) {
                                CoinRow(coin: coin).gaCard(padding: 10, radius: 16)
                            }
                            .buttonStyle(PressableCardStyle())
                        }
                    }
                }
            }
            .padding(GATheme.gutter)
            .padding(.bottom, selecting ? 90 : 24)
        }
        .gaBackground()
        .searchable(text: $model.searchText, prompt: "Search items")
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu {
                    Picker("Sort", selection: $model.sort) {
                        ForEach(ItemSortOrder.allCases) { Text($0.title).tag($0) }
                    }
                } label: { Image(systemName: "arrow.up.arrow.down").frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel("Sort items")
                Button(selecting ? "Done" : "Select") {
                    selecting.toggle()
                    selection.removeAll()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting {
                Button("Move Items (\(selection.count))") { moving = true }
                    .buttonStyle(.gaPrimary)
                    .disabled(selection.isEmpty)
                    .padding(.horizontal, GATheme.gutter)
                    .padding(.vertical, 10)
                    .background(GAColor.cream.opacity(0.97).ignoresSafeArea(edges: .bottom))
            }
        }
        .sheet(isPresented: $moving) {
            MoveItemsSheet(container: container, coinIDs: Array(selection), currentCollectionID: nil) {
                selecting = false
                selection.removeAll()
            }
        }
    }

    private func toggle(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }
}
