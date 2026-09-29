//
//  RootView.swift
//  GoldenArchive
//
//  App layer — onboarding or the main tabs, plus the Add Coin modal.
//

import SwiftUI

@MainActor
final class RootViewModel: ArchiveViewModel {
    @Published var showsOnboarding: Bool
    @Published var loadIssue: String?

    override init(container: AppContainer) {
        showsOnboarding = !container.settings.settings().hasCompletedOnboarding
        loadIssue = container.maintenance.lastLoadIssue
        super.init(container: container)
    }

    override func reload() {
        let shouldShow = !container.settings.settings().hasCompletedOnboarding
        if shouldShow != showsOnboarding { showsOnboarding = shouldShow }
    }

    func completeOnboarding() {
        container.settings.update { $0.hasCompletedOnboarding = true }
        showsOnboarding = false
    }
}

struct RootView: View {
    @EnvironmentObject private var router: AppRouter
    @StateObject private var model: RootViewModel
    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
        #if DEBUG
        QAHooks.seedIfRequested(container)
        #endif
        _model = StateObject(wrappedValue: RootViewModel(container: container))
    }

    var body: some View {
        ZStack {
            if model.showsOnboarding {
                OnboardingView { destination in
                    model.completeOnboarding()
                    switch destination {
                    case .home:
                        router.tab = .home
                    case .addCoin:
                        router.tab = .home
                        router.startAddCoin()
                    case .addManually:
                        router.tab = .home
                        router.startAddCoin(AddCoinRequest(method: .manual))
                    }
                }
                .transition(.opacity)
            } else {
                MainTabView(container: container)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.showsOnboarding)
        .alert("Archive could not be read", isPresented: Binding(
            get: { model.loadIssue != nil && !model.showsOnboarding },
            set: { if !$0 { model.loadIssue = nil } }
        )) {
            Button("OK", role: .cancel) { model.loadIssue = nil }
        } message: {
            Text(model.loadIssue ?? "")
        }
    }
}

struct MainTabView: View {
    let container: AppContainer
    @EnvironmentObject private var router: AppRouter
    #if DEBUG
    @State private var qaSheet: QARouteSheet?
    #endif

    var body: some View {
        TabView(selection: $router.tab) {
            NavigationView { HomeView(container: container) }
                .navigationViewStyle(.stack)
                .tabItem { Label("Hall", systemImage: "building.columns.fill") }
                .tag(AppTab.home)

            NavigationView { CollectionsView(container: container) }
                .navigationViewStyle(.stack)
                .tabItem { Label("Collections", systemImage: "square.grid.2x2.fill") }
                .tag(AppTab.collections)

            NavigationView { AlbumsView(container: container) }
                .navigationViewStyle(.stack)
                .tabItem { Label("Albums", systemImage: "books.vertical.fill") }
                .tag(AppTab.albums)

            NavigationView { ListsView(container: container) }
                .navigationViewStyle(.stack)
                .tabItem { Label("Lists", systemImage: "list.star") }
                .tag(AppTab.lists)

            NavigationView { MoreView(container: container) }
                .navigationViewStyle(.stack)
                .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
                .tag(AppTab.more)
        }
        .fullScreenCover(item: $router.addCoin) { request in
            AddCoinFlowView(container: container, request: request)
                .accentColor(GAColor.navy)
                .environmentObject(container)
                .environmentObject(router)
        }
        .toast($router.toast)
        #if DEBUG
        .onAppear { applyQARoute() }
        .fullScreenCover(item: $qaSheet) { sheet in
            NavigationView { QAHooks.screen(sheet.route, container: container) }
                .navigationViewStyle(.stack)
                .accentColor(GAColor.navy)
                .environmentObject(container)
                .environmentObject(router)
        }
        #endif
    }

    #if DEBUG
    private func applyQARoute() {
        guard let route = QAHooks.route else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            switch route {
            case "home": router.tab = .home
            case "collections": router.tab = .collections
            case "albums": router.tab = .albums
            case "lists-dup": router.openLists(.duplicates)
            case "lists-wish": router.openLists(.wishList)
            case "more": router.tab = .more
            case "add": router.startAddCoin()
            case "add-search": router.startAddCoin(AddCoinRequest(method: .searchCatalog))
            case "add-manual": router.startAddCoin(AddCoinRequest(method: .manual))
            case "add-photo": router.startAddCoin(AddCoinRequest(method: .takePhoto))
            default: qaSheet = QARouteSheet(route: route)
            }
        }
    }
    #endif
}
