//
//  HomeView.swift
//  GoldenArchive
//
//  Presentation layer — Collection Hall. Every figure comes from the
//  user's own records; before the first item there is an honest empty state.
//

import SwiftUI

@MainActor
final class HomeViewModel: ArchiveViewModel {
    @Published private(set) var summary: HomeSummary = .empty
    @Published private(set) var collections: [CoinCollection] = []

    override init(container: AppContainer) {
        super.init(container: container)
        reload()
    }

    override func reload() {
        summary = container.homeSummary.execute()
        collections = container.collections.collections(includeArchived: false)
    }
}

struct HomeView: View {
    let container: AppContainer
    @EnvironmentObject private var router: AppRouter
    @StateObject private var model: HomeViewModel

    init(container: AppContainer) {
        self.container = container
        _model = StateObject(wrappedValue: HomeViewModel(container: container))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                hero
                statsGrid
                quickActions
                if model.summary.isEmpty {
                    emptyState
                } else {
                    if !model.summary.needsReview.isEmpty { needsReviewSection }
                    if !model.summary.incompleteSets.isEmpty { continueSetsSection }
                    recentSection
                    if !model.collections.isEmpty { collectionsSection }
                }
            }
            .padding(.horizontal, GATheme.gutter)
            .padding(.bottom, 32)
        }
        .gaBackground()
        .navigationBarHidden(true)
    }

    // MARK: Header & hero

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("GOLDEN ARCHIVE")
                .font(.caption.weight(.heavy))
                .tracking(1.6)
                .foregroundColor(GAColor.bronzeText)
            Text("Collection Hall")
                .font(GAFont.display(.largeTitle))
                .foregroundColor(GAColor.text)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, 12)
    }

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(GAColor.navyFill)
                .overlay(alignment: .trailing) {
                    ArtworkView(artwork: .homeGuardian)
                        .frame(width: 280, height: 302)
                        .offset(x: 62, y: 8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

            // Keeps the art's glow away from the small text on the left.
            LinearGradient(colors: [GAColor.navy, GAColor.navy.opacity(0.8), GAColor.navy.opacity(0)], startPoint: .leading, endPoint: .trailing)
                .frame(width: 200)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 6) {
                Text("TOTAL ITEMS")
                    .font(.caption.weight(.heavy))
                    .tracking(1.2)
                    .foregroundColor(GAColor.gold)
                Text("\(model.summary.totalItems)")
                    .font(.system(size: 56, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundColor(GAColor.cream)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(heroDetail)
                    .font(.footnote.weight(.medium))
                    .foregroundColor(GAColor.silver)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 10)
                Button {
                    router.startAddCoin()
                } label: {
                    Label("Add Coin", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.ga(.primary, compact: true, fullWidth: false))
            }
            .frame(width: 150, alignment: .leading)
            .padding(20)
        }
        .frame(height: 270)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .goldBezel(radius: 28, width: 3.5)
        .shadow(color: GAColor.navy.opacity(0.28), radius: 16, x: 0, y: 10)
        .accessibilityElement(children: .contain)
    }

    private var heroDetail: String {
        let summary = model.summary
        if summary.isEmpty { return "Nothing recorded yet." }
        return "\(GAFormat.count(summary.recordCount, "record")) in \(GAFormat.count(summary.collectionCount, "collection"))"
    }

    // MARK: Stats

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            NavigationLink(destination: CollectionsView(container: container, isRoot: false)) {
                StatTile(value: "\(model.summary.collectionCount)", label: "Collections", symbol: "square.grid.2x2.fill", tint: GAColor.navy)
            }
            .buttonStyle(PressableCardStyle())

            NavigationLink(destination: AlbumsView(container: container, isRoot: false)) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        IconBadge(symbol: "books.vertical.fill", tint: GAColor.bronze, size: 30)
                        Spacer()
                    }
                    Text(model.summary.overallSetProgress.requiredTotal == 0 ? "—" : model.summary.overallSetProgress.percentText)
                        .font(GAFont.number(.title2))
                        .foregroundColor(GAColor.text)
                    Text("Set Progress")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(GAColor.textSecondary)
                    GAProgressBar(value: model.summary.overallSetProgress.fraction, height: 7)
                }
                .frame(maxWidth: .infinity, minHeight: StatTile.minHeight, alignment: .topLeading)
                .gaCard(padding: 14, radius: 18)
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(PressableCardStyle())

            NavigationLink(destination: NeedsReviewListView(container: container)) {
                StatTile(value: "\(model.summary.needsReview.count)", label: "Needs Review", symbol: "exclamationmark.circle.fill", tint: GAColor.ember)
            }
            .buttonStyle(PressableCardStyle())

            Button {
                router.openLists(.duplicates)
            } label: {
                StatTile(value: "\(model.summary.duplicateExtras)", label: "Duplicates", symbol: "square.on.square.fill", tint: GAColor.navy,
                         detail: model.summary.duplicateGroupCount > 0 ? GAFormat.count(model.summary.duplicateGroupCount, "group") : "extra pieces")
            }
            .buttonStyle(PressableCardStyle())
        }
    }

    // MARK: Quick actions

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Quick Actions")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    quickAction("Add Coin", "plus.circle.fill") { router.startAddCoin() }
                    quickAction("Take Photo", "camera.fill") { router.startAddCoin(AddCoinRequest(method: .takePhoto)) }
                    quickAction("Search Catalog", "magnifyingglass") { router.startAddCoin(AddCoinRequest(method: .searchCatalog)) }
                    quickAction("Wish List", "star.fill") { router.openLists(.wishList) }
                    quickAction("Duplicates", "square.on.square") { router.openLists(.duplicates) }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func quickAction(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                IconBadge(symbol: symbol, tint: GAColor.gold, size: 42)
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundColor(GAColor.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(width: 88, height: 96)
            .gaCard(padding: 8, radius: 18)
        }
        .buttonStyle(PressableCardStyle())
    }

    // MARK: Sections

    private var emptyState: some View {
        VStack(spacing: 14) {
            VStack(spacing: 8) {
                Text("Your hall is empty")
                    .font(GAFont.title(.title3))
                    .foregroundColor(GAColor.text)
                Text("Add your first coin, token or medal. Counts, sets and reports appear here only from items you record.")
                    .font(.subheadline)
                    .foregroundColor(GAColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ArtworkView(artwork: .album)
                .frame(width: 150, height: 112)
                .accessibilityHidden(true)
            HStack(spacing: 10) {
                Button("Add Coin") { router.startAddCoin() }
                    .buttonStyle(.gaPrimary)
                NavigationLink(destination: CollectionsView(container: container, isRoot: false)) {
                    Text("Create Collection")
                }
                .buttonStyle(.gaOutline)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .gaCard()
    }

    private var needsReviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Needs Review", subtitle: "Items with missing details or photo issues")
            VStack(spacing: 0) {
                ForEach(Array(model.summary.needsReview.prefix(3))) { coin in
                    NavigationLink(destination: CoinDetailView(container: container, coinID: coin.id)) {
                        CoinRow(coin: coin, trailing: "Review")
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    if coin.id != model.summary.needsReview.prefix(3).last?.id { Divider() }
                }
                if model.summary.needsReview.count > 3 {
                    Divider()
                    NavigationLink(destination: NeedsReviewListView(container: container)) {
                        Text("See all \(model.summary.needsReview.count)")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(GAColor.bronzeText)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            }
            .gaCard(padding: 12)
        }
    }

    private var continueSetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Continue a Set")
            ForEach(model.summary.incompleteSets) { item in
                NavigationLink(destination: SetBuilderView(container: container, setID: item.set.id)) {
                    SetProgressCard(name: item.set.name, progress: item.progress)
                }
                .buttonStyle(PressableCardStyle())
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Recent Items")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(model.summary.recentItems) { coin in
                        NavigationLink(destination: CoinDetailView(container: container, coinID: coin.id)) {
                            RecentItemCard(coin: coin)
                        }
                        .buttonStyle(PressableCardStyle())
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Open a Collection")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(model.collections) { collection in
                        NavigationLink(destination: CollectionDetailView(container: container, collectionID: collection.id)) {
                            HStack(spacing: 8) {
                                Image(systemName: collection.theme.symbolName)
                                    .foregroundColor(GAColor.bronzeText)
                                Text(collection.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(GAColor.text)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(GAColor.card))
                            .overlay(Capsule().strokeBorder(GAColor.stroke, lineWidth: 1))
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

struct RecentItemCard: View {
    var coin: Coin

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StoredImageView(file: coin.primaryPhoto?.displayFile, maxPixel: 280)
                .frame(width: 128, height: 128)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(coin.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(GAColor.text)
                .lineLimit(2)
                .frame(width: 128, alignment: .leading)
            Text(coin.subtitle.isEmpty ? coin.kind.title : coin.subtitle)
                .font(.caption)
                .foregroundColor(GAColor.textSecondary)
                .lineLimit(1)
                .frame(width: 128, alignment: .leading)
        }
        .gaCard(padding: 10, radius: 20)
        .accessibilityElement(children: .combine)
    }
}

struct SetProgressCard: View {
    var name: String
    var progress: SetProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(name)
                    .font(.headline)
                    .foregroundColor(GAColor.text)
                    .lineLimit(2)
                Spacer()
                Text(progress.percentText)
                    .font(GAFont.number(.headline))
                    .foregroundColor(GAColor.bronzeText)
            }
            GAProgressBar(value: progress.fraction)
            HStack(spacing: 8) {
                StatusPill(text: "\(progress.requiredCollected) collected", tint: GAColor.success)
                StatusPill(text: "\(progress.missing) missing", tint: GAColor.ember)
                if progress.duplicates > 0 {
                    StatusPill(text: "\(progress.duplicates) duplicate", tint: GAColor.navy)
                }
            }
        }
        .gaCard()
        .accessibilityElement(children: .combine)
    }
}

struct NeedsReviewListView: View {
    let container: AppContainer
    @StateObject private var model: HomeViewModel

    init(container: AppContainer) {
        self.container = container
        _model = StateObject(wrappedValue: HomeViewModel(container: container))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if model.summary.needsReview.isEmpty {
                    EmptyStateView(title: "Nothing to review", message: "Items saved with missing details, flagged photos, or marked by you appear here.")
                } else {
                    InfoNote(text: "Open an item, check or complete its details, then tap Mark Reviewed.")
                    VStack(spacing: 0) {
                        ForEach(model.summary.needsReview) { coin in
                            NavigationLink(destination: CoinDetailView(container: container, coinID: coin.id)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    CoinRow(coin: coin)
                                    if !coin.reviewReason.isBlank {
                                        Text(coin.reviewReason)
                                            .font(.caption)
                                            .foregroundColor(GAColor.emberText)
                                            .padding(.leading, 66)
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                    .gaCard(padding: 12)
                }
            }
            .padding(GATheme.gutter)
        }
        .gaBackground()
        .navigationTitle("Needs Review")
        .navigationBarTitleDisplayMode(.inline)
    }
}
