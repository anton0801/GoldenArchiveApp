//
//  MoreView.swift
//  GoldenArchive
//
//  Presentation layer — entry points to the remaining sections.
//

import SwiftUI

struct MoreView: View {
    let container: AppContainer
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 0) {
                    row(DocumentsView(container: container), "Provenance Documents", "Receipts, certificates, old records", "doc.on.doc.fill", GAColor.navy)
                    Divider().padding(.leading, 60)
                    row(GoalsHubView(container: container, tab: .goals), "Collection Goals", "Finish sets and reach targets", "flag.checkered", GAColor.bronze)
                    Divider().padding(.leading, 60)
                    row(GoalsHubView(container: container, tab: .values), "Value Notes", "Dated references with sources", "note.text", GAColor.bronze)
                    Divider().padding(.leading, 60)
                    row(GoalsHubView(container: container, tab: .exhibition), "Exhibition", "A local showcase of chosen items", "building.columns.fill", GAColor.bronze)
                }
                .gaCard(padding: 12)

                VStack(spacing: 0) {
                    row(ReportsView(container: container), "Reports", "Growth, sets, categories, duplicates", "chart.bar.fill", GAColor.navy)
                    Divider().padding(.leading, 60)
                    row(ItemListView(container: container, scope: .all), "All Items", "Search your whole archive", "magnifyingglass", GAColor.navy)
                    Divider().padding(.leading, 60)
                    row(ArchiveListView(container: container), "Archive", "Hidden items, collections and sets", "archivebox.fill", GAColor.navy)
                }
                .gaCard(padding: 12)

                VStack(spacing: 0) {
                    Button {
                        router.startAddCoin(AddCoinRequest(method: .searchCatalog))
                    } label: {
                        ActionRowLabel(title: "Search Catalog", subtitle: "Reference suggestions for a new item", symbol: "books.vertical.fill", tint: GAColor.navy)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 60)
                    row(SettingsView(container: container), "Settings", "Currency, units, catalog, backup", "gearshape.fill", GAColor.navy)
                }
                .gaCard(padding: 12)
            }
            .padding(GATheme.gutter)
            .padding(.bottom, 24)
        }
        .gaBackground()
        .navigationTitle("More")
        .navigationBarTitleDisplayMode(.large)
    }

    private func row<Destination: View>(_ destination: Destination, _ title: String, _ subtitle: String, _ symbol: String, _ tint: Color) -> some View {
        NavigationLink(destination: destination) {
            ActionRowLabel(title: title, subtitle: subtitle, symbol: symbol, tint: tint)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}
