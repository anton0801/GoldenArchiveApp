//
//  AppRouter.swift
//  GoldenArchive
//
//  App layer — tab selection, the Add Coin flow and transient messages.
//

import SwiftUI
import Combine

enum AppTab: Hashable {
    case home
    case collections
    case albums
    case lists
    case more
}

enum ListsSegment: String, CaseIterable, Identifiable {
    case duplicates
    case wishList

    var id: String { rawValue }
    var title: String { self == .duplicates ? "Duplicates" : "Wish List" }
}

enum AddMethod: String, Hashable {
    case takePhoto
    case choosePhoto
    case searchCatalog
    case manual
}

/// Everything the Add Coin flow may be started with. Nothing here creates
/// a record — only Review & Save does.
struct AddCoinRequest: Identifiable {
    let id = UUID()
    var method: AddMethod?
    var collectionID: UUID?
    var prefill: ExpectedAttributes?
    var prefillName: String?
    var kind: ItemKind = .coin
    var pendingSlot: SlotReference?
    var wishID: UUID?
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var message: String
    var symbol: String = "checkmark.seal.fill"
}

final class AppRouter: ObservableObject {
    @Published var tab: AppTab = .home
    @Published var listsSegment: ListsSegment = .duplicates
    @Published var addCoin: AddCoinRequest?
    @Published var toast: Toast?

    func startAddCoin(_ request: AddCoinRequest = AddCoinRequest()) {
        guard addCoin == nil else { return }
        addCoin = request
    }

    func show(_ message: String, symbol: String = "checkmark.seal.fill") {
        toast = Toast(message: message, symbol: symbol)
    }

    func openLists(_ segment: ListsSegment) {
        listsSegment = segment
        tab = .lists
    }
}
