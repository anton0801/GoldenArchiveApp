//
//  QAHooks.swift
//  GoldenArchive
//
//  DEBUG builds only. Launch arguments used for screenshot QA on the
//  simulator: `-qaSeed` fills an EMPTY archive with sample records and
//  `-qaRoute <name>` opens a screen. Release builds contain none of this,
//  and nothing runs unless the arguments are passed explicitly.
//

#if DEBUG
import SwiftUI
import UIKit

enum QAHooks {
    static var route: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-qaRoute"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    static var shouldSeed: Bool { ProcessInfo.processInfo.arguments.contains("-qaSeed") }

    static func seedIfRequested(_ container: AppContainer) {
        if ProcessInfo.processInfo.arguments.contains("-qaNoOnboarding") {
            container.settings.update { $0.hasCompletedOnboarding = true }
        }
        guard shouldSeed, container.coins.coins(includeArchived: true).isEmpty else { return }
        container.settings.update { $0.hasCompletedOnboarding = true }
        let now = Date()
        let day: TimeInterval = 86_400

        let silver = container.collectionUseCase.create(name: "US Silver Dollars", theme: .country, tags: ["silver", "usa"], completionNote: "Missing the 1921-D Peace")
        let euro = container.collectionUseCase.create(name: "Euro Circulation", theme: .era, tags: ["euro"], completionNote: "")

        func photo(_ hue: UIColor, side: PhotoSide) -> CoinPhoto? {
            let size = CGSize(width: 900, height: 900)
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                UIColor(white: 0.86, alpha: 1).setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                let rect = CGRect(x: 120, y: 120, width: 660, height: 660)
                hue.setFill()
                UIBezierPath(ovalIn: rect).fill()
                hue.withAlphaComponent(0.6).setStroke()
                let ring = UIBezierPath(ovalIn: rect.insetBy(dx: 50, dy: 50))
                ring.lineWidth = 14
                ring.stroke()
            }
            guard let data = image.jpegData(compressionQuality: 0.9) else { return nil }
            return try? container.photoIntake.intake(data: data, contentType: "image/jpeg", side: side)
        }

        let silverTone = UIColor(red: 0.74, green: 0.76, blue: 0.79, alpha: 1)
        let goldTone = UIColor(red: 0.85, green: 0.68, blue: 0.3, alpha: 1)
        let copperTone = UIColor(red: 0.72, green: 0.45, blue: 0.25, alpha: 1)

        func add(_ name: String, _ country: String, _ year: Int?, _ denomination: String, mint: String = "", material: String, diameter: Double? = nil,
                 weight: Double? = nil, quantity: Int = 1, collection: UUID?, tone: UIColor?, ageDays: Double, review: Bool = false) -> Coin? {
            var form = CoinForm()
            form.name = name
            form.country = country
            form.yearText = year.map { "\($0)" } ?? ""
            form.denomination = denomination
            form.mint = mint
            form.material = material
            form.diameterText = diameter.map { NumberText.format($0) } ?? ""
            form.weightText = weight.map { NumberText.format($0) } ?? ""
            form.quantity = quantity
            form.collectionID = collection
            form.needsReview = review
            form.reviewReason = review ? "Check the mint mark under a loupe." : ""
            let photos = tone.map { [photo($0, side: .obverse), photo($0, side: .reverse)].compactMap { $0 } } ?? []
            let request = SaveCoinRequest(coinID: UUID(), form: form, photos: photos, catalogReference: nil, pendingSlot: nil, fulfilledWishID: nil)
            guard case .success(let outcome) = container.saveCoin.execute(request) else { return nil }
            var coin = outcome.coin
            coin.createdAt = now.addingTimeInterval(-ageDays * day)
            container.coins.save(coin)
            return coin
        }

        let morgan = add("Morgan Dollar 1881-S", "United States", 1881, "1 dollar", mint: "S", material: "Silver .900", diameter: 38.1, weight: 26.73, collection: silver.id, tone: silverTone, ageDays: 200)
        let morgan2 = add("Morgan Dollar 1881-S", "United States", 1881, "1 dollar", mint: "S", material: "Silver .900", diameter: 38.1, weight: 26.73, collection: silver.id, tone: silverTone, ageDays: 120)
        _ = add("Peace Dollar 1922", "United States", 1922, "1 dollar", mint: "P", material: "Silver .900", diameter: 38.1, weight: 26.73, collection: silver.id, tone: silverTone, ageDays: 90)
        _ = add("Silver Eagle 2021", "United States", 2021, "1 dollar", material: "Silver .999", quantity: 3, collection: silver.id, tone: silverTone, ageDays: 40)
        let delaware = add("Delaware Quarter", "United States", 1999, "25 cents", mint: "P", material: "Copper-nickel clad copper", collection: nil, tone: silverTone, ageDays: 30)
        _ = add("Pennsylvania Quarter", "United States", 1999, "25 cents", mint: "D", material: "Copper-nickel clad copper", collection: nil, tone: silverTone, ageDays: 25)
        _ = add("2 Euro Germany", "Germany", 2002, "2 euro", mint: "A", material: "Bimetallic", collection: euro.id, tone: goldTone, ageDays: 14)
        _ = add("Unknown bronze token", "", nil, "", material: "Bronze", collection: nil, tone: copperTone, ageDays: 3, review: true)
        _ = add("Coronation medal", "United Kingdom", 1937, "", material: "Bronze", collection: nil, tone: nil, ageDays: 1)

        // Set from the State Quarters template with two slots filled.
        let slots = SetEditingUseCase.slots(from: BuiltInTemplates.usStateQuarters, country: "", year: nil)
        let set = container.setEditing.createSet(name: "50 State Quarters", collectionID: nil, note: "Philadelphia or Denver, circulated is fine.", slots: slots, templateName: BuiltInTemplates.usStateQuarters.name)
        if let delaware { _ = container.linkSlot.execute(coinID: delaware.id, slot: SlotReference(setID: set.id, slotID: slots[0].id), confirmQuantity: false) }
        if let pa = container.coins.coins(includeArchived: false).first(where: { $0.name == "Pennsylvania Quarter" }) {
            _ = container.linkSlot.execute(coinID: pa.id, slot: SlotReference(setID: set.id, slotID: slots[1].id), confirmQuantity: false)
        }
        container.setEditing.addMissingToWishList(setID: set.id)

        if let morgan, let morgan2 { container.duplicateUseCase.markDuplicate(morgan2.id, of: morgan.id) }

        if let morgan {
            let obs = ConditionObservation(coinID: morgan.id, observedOn: now.addingTimeInterval(-100 * day), wear: .light, scratches: "Fine hairline on the obverse field", color: "Light toning at the rim", userGrade: "About XF", note: "Bought at the spring fair.", createdAt: now, updatedAt: now)
            container.conditionUseCase.save(obs)
            _ = container.valueNoteUseCase.add(coinID: morgan.id, kind: .externalReference, amountText: "62", currency: "USD", sourceName: "Dealer price list", sourceURL: "https://example.com", valueDate: now.addingTimeInterval(-60 * day), note: "")
            _ = container.valueNoteUseCase.add(coinID: morgan.id, kind: .personalEstimate, amountText: "70", currency: "USD", sourceName: "My own estimate", sourceURL: "", valueDate: now.addingTimeInterval(-5 * day), note: "")
            let doc = ProvenanceDocument(type: .receipt, title: "Spring coin fair receipt", date: now.addingTimeInterval(-100 * day), sourceNote: "Table 14", pricePaid: MoneyAmount(amount: 58, currency: "USD"), linkedCoinIDs: [morgan.id], createdAt: now, updatedAt: now)
            container.documentUseCase.save(doc)
            if let data = UIImage(systemName: "doc.text")?.withTintColor(.darkGray).pngData() {
                container.documentUseCase.attachData(documentID: doc.id, data: data, contentType: "image/png", originalName: "receipt.png")
            }
            container.exhibitionUseCase.create(title: "Silver of the Old West", intro: "Dollars from the San Francisco mint.", coinIDs: [morgan.id])
        }
        let goal = CollectionGoal(id: UUID(), title: "Finish the state quarters", target: .completeSets([set.id]), targetDate: now.addingTimeInterval(200 * day), note: "", createdAt: now, updatedAt: now)
        container.goalUseCase.save(goal)
    }

    @ViewBuilder
    static func screen(_ route: String, container: AppContainer) -> some View {
        let coin = container.coins.coins(includeArchived: false).first { $0.name.hasPrefix("Morgan") }
        let set = container.sets.sets(includeArchived: false).first
        switch route {
        case "coin": if let coin { CoinDetailView(container: container, coinID: coin.id) }
        case "set": if let set { SetBuilderView(container: container, setID: set.id) }
        case "condition": if let coin { ConditionNotesView(container: container, coinID: coin.id) }
        case "collection": if let id = container.collections.collections(includeArchived: false).first?.id { CollectionDetailView(container: container, collectionID: id) }
        case "reports": ReportsView(container: container)
        case "settings": SettingsView(container: container)
        case "documents": DocumentsView(container: container)
        case "document": if let id = container.documents.documents().first?.id { DocumentDetailView(container: container, documentID: id) }
        case "goals": GoalsHubView(container: container, tab: .goals)
        case "values": GoalsHubView(container: container, tab: .values)
        case "exhibition": GoalsHubView(container: container, tab: .exhibition)
        case "archive": ArchiveListView(container: container)
        case "duplicate": if let id = container.duplicates.groups().first?.id { DuplicateGroupView(container: container, groupID: id) }
        default: EmptyView()
        }
    }
}

struct QARouteSheet: Identifiable {
    let id = UUID()
    var route: String
}
#endif
