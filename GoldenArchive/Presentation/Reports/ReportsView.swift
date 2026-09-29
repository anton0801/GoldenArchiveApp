//
//  ReportsView.swift
//  GoldenArchive
//
//  Presentation layer — reports built only from the user's real records.
//  Every figure can be opened to show the items behind it.
//

import SwiftUI

@MainActor
final class ReportsViewModel: ArchiveViewModel {
    @Published var period: ReportPeriod = .year { didSet { reload() } }
    @Published var collectionID: UUID? { didSet { reload() } }
    @Published var kind: ItemKind? { didSet { reload() } }
    @Published private(set) var report: CollectionReport?
    @Published private(set) var collections: [CoinCollection] = []

    override init(container: AppContainer) {
        super.init(container: container)
        reload()
    }

    override func reload() {
        collections = container.collections.collections(includeArchived: false)
        report = container.buildReport.execute(period: period, filter: ReportFilter(collectionID: collectionID, kind: kind))
    }
}

struct ReportsView: View {
    let container: AppContainer
    @StateObject private var model: ReportsViewModel

    init(container: AppContainer) {
        self.container = container
        _model = StateObject(wrappedValue: ReportsViewModel(container: container))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                filters
                if let report = model.report, report.hasData {
                    summary(report)
                    growth(report)
                    if !report.sets.isEmpty { setsSection(report) }
                    categorySection("By Country", report.byCountry)
                    categorySection("By Material", report.byMaterial)
                    categorySection("By Type", report.byKind)
                    duplicatesSection(report)
                    valueSection(report)
                } else {
                    EmptyStateView(
                        artwork: .exhibitionWreath,
                        artSize: CGSize(width: 150, height: 120),
                        title: "No report yet",
                        message: model.collectionID != nil || model.kind != nil
                            ? "No active items match these filters."
                            : "Reports appear after you add real items. Nothing is estimated or filled in for you."
                    )
                }
            }
            .padding(GATheme.gutter)
            .padding(.bottom, 24)
        }
        .gaBackground()
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            GASegmented(options: ReportPeriod.allCases, selection: $model.period) { $0.title }
            HStack(spacing: 10) {
                Menu {
                    Button("All collections") { model.collectionID = nil }
                    ForEach(model.collections) { collection in
                        Button(collection.name) { model.collectionID = collection.id }
                    }
                } label: {
                    filterLabel(model.collections.first { $0.id == model.collectionID }?.name ?? "All collections", "folder")
                }
                Menu {
                    Button("All types") { model.kind = nil }
                    ForEach(ItemKind.allCases) { kind in Button(kind.pluralTitle) { model.kind = kind } }
                } label: {
                    filterLabel(model.kind?.pluralTitle ?? "All types", "circle.grid.2x2")
                }
            }
        }
    }

    private func filterLabel(_ title: String, _ symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(title).lineLimit(1)
            Image(systemName: "chevron.down").font(.caption2.weight(.bold))
        }
        .font(.subheadline.weight(.semibold))
        .foregroundColor(GAColor.text)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(GAColor.card))
        .overlay(Capsule().strokeBorder(GAColor.stroke, lineWidth: 1))
    }

    private func sourceLink(_ ids: [UUID], _ title: String) -> some View {
        NavigationLink(destination: ItemListView(container: container, scope: .ids(ids, title: title))) {
            Label("Open Source Items", systemImage: "list.bullet.rectangle")
                .font(.footnote.weight(.bold))
                .foregroundColor(GAColor.bronzeText)
        }
        .disabled(ids.isEmpty)
    }

    private func summary(_ report: CollectionReport) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
            StatTile(value: "\(report.totalPieces)", label: "Pieces", symbol: "circle.circle.fill", tint: GAColor.bronze)
            StatTile(value: "\(report.sourceCoins.count)", label: "Records", symbol: "tray.full.fill", tint: GAColor.navy)
            StatTile(value: "\(report.addedInPeriod.count)", label: "Added", symbol: "plus.circle.fill", tint: GAColor.success)
        }
    }

    private func growth(_ report: CollectionReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Collection Growth", subtitle: "Pieces added per \(report.period == .days30 || report.period == .days90 ? "week" : "month")")
            let maxAdded = max(1, report.growth.map(\.added).max() ?? 1)
            let labelStride = max(1, Int((Double(report.growth.count) / 6).rounded(.up)))
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(report.growth.enumerated()), id: \.element.id) { index, bucket in
                    NavigationLink(destination: ItemListView(container: container, scope: .ids(bucket.coinIDs, title: "Added \(bucket.label)"))) {
                        VStack(spacing: 6) {
                            Text(bucket.added > 0 ? "\(bucket.added)" : " ")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundColor(GAColor.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(bucket.added > 0 ? AnyShapeStyle(GAColor.goldFill) : AnyShapeStyle(GAColor.creamDeep))
                                .frame(height: max(4, CGFloat(bucket.added) / CGFloat(maxAdded) * 110))
                                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(GAColor.bronze.opacity(bucket.added > 0 ? 0.5 : 0.15), lineWidth: 1))
                            Text(index % labelStride == 0 || index == report.growth.count - 1 ? bucket.label : " ")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(GAColor.textSecondary)
                                .lineLimit(1)
                                .fixedSize()
                                .frame(width: 10)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(bucket.coinIDs.isEmpty)
                    .accessibilityLabel("\(bucket.label): \(bucket.added) added, \(bucket.cumulative) in total")
                }
            }
            .frame(height: 160, alignment: .bottom)
            .padding(.horizontal, 8)
            if let last = report.growth.last {
                Text("\(last.cumulative) pieces at the end of the period")
                    .font(.footnote)
                    .foregroundColor(GAColor.textSecondary)
            }
            sourceLink(report.addedInPeriod.map(\.id), "Added in \(report.period.title)")
        }
        .gaCard()
    }

    private func setsSection(_ report: CollectionReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Set Completion")
            ForEach(report.sets) { item in
                NavigationLink(destination: SetBuilderView(container: container, setID: item.set.id)) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.set.name).font(.subheadline.weight(.semibold)).foregroundColor(GAColor.text).lineLimit(1)
                            Spacer()
                            Text("\(item.progress.requiredCollected)/\(item.progress.requiredTotal)")
                                .font(.footnote.weight(.bold).monospacedDigit())
                                .foregroundColor(GAColor.textSecondary)
                        }
                        GAProgressBar(value: item.progress.fraction, height: 8)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .gaCard()
    }

    private func categorySection(_ title: String, _ categories: [CategoryCount]) -> some View {
        let top = Array(categories.prefix(8))
        let maxCount = max(1, top.map(\.count).max() ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title)
            ForEach(top) { category in
                NavigationLink(destination: ItemListView(container: container, scope: .ids(category.coinIDs, title: category.name))) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(category.name).font(.subheadline).foregroundColor(GAColor.text).lineLimit(1)
                            Spacer()
                            Text("\(category.count)").font(.subheadline.weight(.bold).monospacedDigit()).foregroundColor(GAColor.text)
                        }
                        GeometryReader { proxy in
                            Capsule()
                                .fill(GAColor.navyFill)
                                .frame(width: max(6, proxy.size.width * CGFloat(category.count) / CGFloat(maxCount)))
                        }
                        .frame(height: 8)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(category.name): \(category.count) pieces")
            }
            if categories.count > top.count {
                Text("+\(categories.count - top.count) more").font(.caption).foregroundColor(GAColor.textSecondary)
            }
        }
        .gaCard()
    }

    private func duplicatesSection(_ report: CollectionReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Duplicates")
            Text("\(GAFormat.count(report.duplicateGroups.count, "duplicate group")) · \(GAFormat.count(report.duplicateExtras, "extra piece"))")
                .font(.subheadline)
                .foregroundColor(GAColor.text)
            sourceLink(report.duplicateGroups.flatMap(\.coinIDs), "Duplicates")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gaCard()
    }

    private func valueSection(_ report: CollectionReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Value Notes History", subtitle: "Reference Notes — not appraisals or sale prices")
            if report.valueHistory.isEmpty {
                Text("No value notes dated in this period.")
                    .font(.footnote)
                    .foregroundColor(GAColor.textSecondary)
            } else {
                ForEach(report.valueHistory.suffix(12).reversed()) { point in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(point.coinName).font(.subheadline.weight(.semibold)).foregroundColor(GAColor.text).lineLimit(1)
                            Text("\(point.note.sourceName) · \(GAFormat.day(point.note.valueDate))").font(.caption).foregroundColor(GAColor.textSecondary)
                        }
                        Spacer()
                        Text(GAFormat.money(point.note.amount)).font(.subheadline.weight(.bold).monospacedDigit()).foregroundColor(GAColor.text)
                    }
                }
            }
            if !report.referenceTotals.isEmpty {
                Divider()
                Text("REFERENCE NOTES TOTAL (latest per item)")
                    .font(.caption.weight(.heavy))
                    .foregroundColor(GAColor.bronzeText)
                ForEach(report.referenceTotals, id: \.currency) { total in
                    Text(GAFormat.money(total)).font(GAFont.number(.headline)).foregroundColor(GAColor.text)
                }
            }
            sourceLink(Array(Set(report.valueHistory.map(\.note.coinID))), "Items with value notes")
        }
        .gaCard()
    }
}

// MARK: - Archive

@MainActor
final class ArchiveListViewModel: ArchiveViewModel {
    @Published private(set) var coins: [Coin] = []
    @Published private(set) var collections: [CoinCollection] = []
    @Published private(set) var sets: [CoinSet] = []

    override init(container: AppContainer) {
        super.init(container: container)
        reload()
    }

    override func reload() {
        coins = container.coins.coins(includeArchived: true).filter(\.isArchived).sorted { ($0.archivedAt ?? $0.updatedAt) > ($1.archivedAt ?? $1.updatedAt) }
        collections = container.collections.collections(includeArchived: true).filter(\.isArchived)
        sets = container.sets.sets(includeArchived: true).filter(\.isArchived)
    }

    var isEmpty: Bool { coins.isEmpty && collections.isEmpty && sets.isEmpty }

    func restoreCoin(_ id: UUID) { container.coinState.restore(coinID: id) }
    func restoreCollection(_ id: UUID) { container.collectionUseCase.archive(id: id, archived: false) }
    func restoreSet(_ id: UUID) { container.setEditing.archive(setID: id, archived: false) }
}

struct ArchiveListView: View {
    let container: AppContainer
    @EnvironmentObject private var router: AppRouter
    @StateObject private var model: ArchiveListViewModel

    init(container: AppContainer) {
        self.container = container
        _model = StateObject(wrappedValue: ArchiveListViewModel(container: container))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if model.isEmpty {
                    EmptyStateView(
                        artwork: .exhibitionWreath,
                        artSize: CGSize(width: 150, height: 120),
                        title: "Archive is empty",
                        message: "Archived items, collections and sets are hidden from Home and reports but kept safely here until you restore them."
                    )
                }
                if !model.coins.isEmpty {
                    SectionHeader(title: "Items")
                    ForEach(model.coins) { coin in
                        HStack {
                            NavigationLink(destination: CoinDetailView(container: container, coinID: coin.id)) {
                                CoinRow(coin: coin, showsChevron: false)
                            }
                            .buttonStyle(.plain)
                            Button("Restore") {
                                model.restoreCoin(coin.id)
                                router.show("Restored", symbol: "arrow.uturn.backward.circle.fill")
                            }
                            .buttonStyle(.ga(.quiet, compact: true, fullWidth: false))
                        }
                        .gaCard(padding: 10, radius: 16)
                    }
                }
                if !model.collections.isEmpty {
                    SectionHeader(title: "Collections")
                    ForEach(model.collections) { collection in
                        restoreRow(collection.name, "folder.fill") { model.restoreCollection(collection.id) }
                    }
                }
                if !model.sets.isEmpty {
                    SectionHeader(title: "Sets")
                    ForEach(model.sets) { set in
                        restoreRow(set.name, "square.grid.3x3.fill") { model.restoreSet(set.id) }
                    }
                }
            }
            .padding(GATheme.gutter)
            .padding(.bottom, 24)
        }
        .gaBackground()
        .navigationTitle("Archive")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func restoreRow(_ title: String, _ symbol: String, restore: @escaping () -> Void) -> some View {
        HStack {
            IconBadge(symbol: symbol, tint: GAColor.navy, size: 36)
            Text(title).font(.body.weight(.semibold)).foregroundColor(GAColor.text)
            Spacer()
            Button("Restore") {
                restore()
                router.show("Restored", symbol: "arrow.uturn.backward.circle.fill")
            }
            .buttonStyle(.ga(.quiet, compact: true, fullWidth: false))
        }
        .gaCard(padding: 10, radius: 16)
    }
}
