//
//  QASelfTest.swift
//  GoldenArchive
//
//  DEBUG builds only. `-qaSelfTest` runs the domain rules against a
//  throw-away in-memory archive and exits with the result.
//

//#if DEBUG
//import Foundation
//import UIKit
//
//@MainActor
//enum QASelfTest {
//    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-qaSelfTest") }
//
//    private static var failures = 0
//
//    private static func check(_ condition: Bool, _ name: String) {
//        if !condition { failures += 1 }
//    }
//
//    static func run() async -> Bool {
//        let c = AppContainer(inMemory: true)
//        let now = Date()
//
//        // 1. Validation
//        var form = CoinForm()
//        if case .failure(let f) = c.validator.validate(form, units: .metric) {
//            check(f.errors.contains { $0.field == .name }, "name is required")
//        } else { check(false, "name is required") }
//        form.name = "Test"
//        form.yearText = "3000"
//        form.diameterText = "38,1"
//        if case .failure(let f) = c.validator.validate(form, units: .metric) {
//            check(f.errors.contains { $0.field == .year } && !f.errors.contains { $0.field == .diameter }, "year range checked, comma decimals accepted")
//        } else { check(false, "year range checked") }
//        form.yearText = "44"; form.isBC = true
//        if case .success(let v) = c.validator.validate(form, units: .metric) {
//            check(v.year == -44 && abs((v.diameterMM ?? 0) - 38.1) < 0.001, "BC year and diameter parsed")
//        } else { check(false, "BC year parsed") }
//
//        // 2. Idempotent save + auto review
//        var morganForm = CoinForm()
//        morganForm.name = "Morgan Dollar"
//        morganForm.country = "United States"
//        morganForm.yearText = "1881"
//        morganForm.denomination = "1 dollar"
//        morganForm.mint = "S"
//        let draftID = UUID()
//        let request = SaveCoinRequest(coinID: draftID, form: morganForm, photos: [], catalogReference: nil, pendingSlot: nil, fulfilledWishID: nil)
//        _ = c.saveCoin.execute(request)
//        _ = c.saveCoin.execute(request)
//        check(c.coins.coins(includeArchived: true).count == 1, "saving the same draft twice creates one record")
//        check(c.coins.coin(id: draftID)?.needsReview == false, "complete item is not flagged for review")
//        var sparse = CoinForm(); sparse.name = "Mystery token"
//        guard case .success(let sparseOutcome) = c.saveCoin.execute(SaveCoinRequest(coinID: UUID(), form: sparse, photos: [], catalogReference: nil, pendingSlot: nil, fulfilledWishID: nil)) else { return }
//        check(sparseOutcome.coin.needsReview, "item missing country/year/denomination goes to Needs Review")
//
//        // 3. Sets & quantity rule
//        let set = c.setEditing.createSet(name: "Test set", collectionID: nil, note: "", slots: [
//            SetSlot(title: "A"), SetSlot(title: "B"), SetSlot(title: "C"), SetSlot(title: "Opt", isOptional: true)
//        ], templateName: nil)
//        let slotA = SlotReference(setID: set.id, slotID: set.slots[0].id)
//        let slotB = SlotReference(setID: set.id, slotID: set.slots[1].id)
//        check(c.linkSlot.execute(coinID: draftID, slot: slotA, confirmQuantity: false) == .linked, "link first slot")
//        let second = c.linkSlot.execute(coinID: draftID, slot: slotB, confirmQuantity: false)
//        check(second == .needsQuantityConfirmation(currentQuantity: 1, requiredQuantity: 2, otherSlots: ["Test set — A"]), "second unique slot asks to confirm quantity")
//        check(c.linkSlot.execute(coinID: draftID, slot: slotB, confirmQuantity: true) == .linked && c.coins.coin(id: draftID)?.quantity == 2, "confirming raises quantity and links")
//        let calc = SetProgressCalculator(coins: c.coins.coins(includeArchived: true), sets: c.sets.sets(includeArchived: true), groups: [])
//        let progress = calc.progress(for: c.sets.set(id: set.id)!)
//        check(progress.requiredCollected == 2 && progress.requiredTotal == 3 && progress.optionalTotal == 1, "progress counts required slots only")
//        c.linkSlot.unlink(slotB)
//        let after = SetProgressCalculator(coins: c.coins.coins(includeArchived: true), sets: c.sets.sets(includeArchived: true), groups: []).progress(for: c.sets.set(id: set.id)!)
//        check(after.requiredCollected == 1, "progress updates after unlink")
//        check(c.setEditing.addMissingToWishList(setID: set.id) == 2 && c.setEditing.addMissingToWishList(setID: set.id) == 0, "missing slots added to wish list once")
//
//        // 4. Wish → acquired via save, slot linked
//        let wish = c.wishes.wishes().first { $0.linkedSlot?.slotID == set.slots[2].id }!
//        var acquiredForm = CoinForm(); acquiredForm.name = "Slot C coin"; acquiredForm.country = "X"; acquiredForm.yearText = "2000"; acquiredForm.denomination = "1"
//        _ = c.saveCoin.execute(SaveCoinRequest(coinID: UUID(), form: acquiredForm, photos: [], catalogReference: nil, pendingSlot: nil, fulfilledWishID: wish.id))
//        check(c.wishes.wish(id: wish.id)?.status == .acquired && c.sets.set(id: set.id)?.slots[2].linkedCoinID != nil, "Mark Acquired flow closes wish and fills its slot")
//
//        // 5. Photos & documents on delete
//        let pixel = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { ctx in UIColor.gray.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64)) }
//        let photo = try! c.photoIntake.intake(data: pixel.jpegData(compressionQuality: 0.9)!, contentType: "image/jpeg", side: .obverse)
//        let cropped = try! c.photoIntake.applyCrop(to: photo, quarterTurns: 1, region: CropRegion(x: 0.1, y: 0.1, width: 0.5, height: 0.5))
//        check(cropped.cropped != nil && cropped.original == photo.original && c.media.exists(photo.original), "crop is a separate file; original kept")
//        c.coinState.updatePhotos(coinID: draftID, photos: [cropped])
//        let shared = ProvenanceDocument(title: "Shared", linkedCoinIDs: [draftID, sparseOutcome.coin.id], createdAt: now, updatedAt: now)
//        let exclusive = ProvenanceDocument(title: "Exclusive", linkedCoinIDs: [draftID], createdAt: now, updatedAt: now)
//        c.documentUseCase.save(shared); c.documentUseCase.save(exclusive)
//        let impact = c.deleteCoin.impact(coinID: draftID)!
//        check(impact.slots.count == 1 && impact.sharedDocuments.count == 1 && impact.exclusiveDocuments.count == 1 && impact.photoFileCount == 2, "deletion impact lists slots, documents and files")
//        c.deleteCoin.execute(coinID: draftID, alsoDeleteExclusiveDocuments: false)
//        check(c.coins.coin(id: draftID) == nil && c.documents.document(id: exclusive.id)?.linkedCoinIDs.isEmpty == true && c.documents.document(id: shared.id)?.linkedCoinIDs == [sparseOutcome.coin.id], "documents are kept and unlinked by default")
//        check(!c.media.exists(cropped.original) && !c.media.exists(cropped.cropped!), "photo files of the deleted item are removed")
//        check(c.sets.set(id: set.id)?.slots[0].linkedCoinID == nil, "slot emptied after delete")
//
//        // 6. Collections never delete items
//        let col = c.collectionUseCase.create(name: "Temp", theme: .custom, tags: [], completionNote: "")
//        c.coinState.move(coinIDs: [sparseOutcome.coin.id], to: col.id, collectionName: col.name)
//        c.collectionUseCase.delete(id: col.id, choice: .keepUnsorted)
//        check(c.coins.coin(id: sparseOutcome.coin.id)?.collectionID == nil, "deleting a collection keeps its items Unsorted")
//
//        // 7. Duplicates & merge
//        var a = CoinForm(); a.name = "Dup A"; a.country = "Canada"; a.yearText = "1990"; a.denomination = "1 cent"; a.material = "Bronze"
//        var b = CoinForm(); b.name = "Dup B"; b.country = "Canada"; b.yearText = "1990"; b.denomination = "1 cent"
//        let idA = UUID(), idB = UUID()
//        _ = c.saveCoin.execute(SaveCoinRequest(coinID: idA, form: a, photos: [], catalogReference: nil, pendingSlot: nil, fulfilledWishID: nil))
//        let photoB = try! c.photoIntake.intake(data: pixel.jpegData(compressionQuality: 0.9)!, contentType: "image/jpeg", side: .obverse)
//        _ = c.saveCoin.execute(SaveCoinRequest(coinID: idB, form: b, photos: [photoB], catalogReference: nil, pendingSlot: nil, fulfilledWishID: nil))
//        check(DuplicateFinder.possibleDuplicates(coins: c.coins.coins(includeArchived: true), groups: []).count == 1, "look-alike records are suggested")
//        let group = c.duplicateUseCase.markDuplicate(idB, of: idA)!
//        let merged = c.duplicateUseCase.applyMerge(groupID: group.id, primaryID: idA, fields: [.material, .country], overwrite: false, units: .metric)
//        check(merged == 1 && c.coins.coin(id: idB)?.material == "Bronze" && c.coins.coin(id: idB)?.photos.count == 1, "merge fills blanks only and keeps photos")
//
//        // 8. Value notes need a source
//        if case .failure(let e) = c.valueNoteUseCase.add(coinID: idA, kind: .personalEstimate, amountText: "10", currency: "USD", sourceName: " ", sourceURL: "", valueDate: now, note: "") {
//            check(e == .source, "value note without source is rejected")
//        } else { check(false, "value note without source is rejected") }
//        if case .success = c.valueNoteUseCase.add(coinID: idA, kind: .externalReference, amountText: "12,50", currency: "eur", sourceName: "List", sourceURL: "https://example.com", valueDate: now, note: "") {
//            check(ValueNoteUseCase.referenceTotals(notes: c.valueNotes.valueNotes(coinID: nil), coinIDs: [idA]).first?.amount == Decimal(string: "12.5"), "reference total sums latest note")
//        } else { check(false, "valid value note saved") }
//
//        // 9. Offline catalog
//        c.settings.update { $0.offlineReferenceEnabled = true; $0.numistaEnabled = false }
//        let (found, _) = await c.searchCatalog.execute(CatalogQuery(text: "", country: "USA", year: 1881, denomination: "$1"))
//        check(found.first?.candidate.title == "Morgan Dollar" && found.first?.assessment.strength == .strong, "offline reference suggests Morgan Dollar as strong metadata match")
//        let (none, _) = await c.searchCatalog.execute(CatalogQuery(text: "zzzz"))
//        check(none.isEmpty, "unknown text returns no candidates")
//
//        // 10. Backup round trip & safe import
//        do {
//            let url = try c.exportBackup.execute(appVersion: "test")
//            let validation = c.validateImport.execute(data: try Data(contentsOf: url))
//            check(validation.canImport, "exported backup validates")
//            let target = AppContainer(inMemory: true)
//            _ = try target.applyImport.execute(validation.package!, mode: .replace)
//            check(target.coins.coins(includeArchived: true).count == c.coins.coins(includeArchived: true).count
//                  && target.coins.coin(id: idB)?.photos.first.map { target.media.exists($0.original) } == true, "replace import restores records and files")
//            let before = target.coins.coins(includeArchived: true).count
//            let bad = target.validateImport.execute(data: Data("{\"nope\":1}".utf8))
//            check(!bad.canImport && target.coins.coins(includeArchived: true).count == before, "invalid file is rejected without changes")
//            _ = try target.applyImport.execute(validation.package!, mode: .merge)
//            check(target.coins.coins(includeArchived: true).count == before, "merge import does not duplicate existing records")
//        } catch {
//            check(false, "backup round trip threw \(error)")
//        }
//
//        // 11. Rebuild index repairs dangling references
//        var snapshot = c.maintenance.snapshot()
//        snapshot.valueNotes.append(ValueNote(id: UUID(), coinID: UUID(), kind: .personalEstimate, amount: MoneyAmount(amount: 1, currency: "USD"), sourceName: "x", sourceURL: "", valueDate: now, note: "", createdAt: now))
//        try? c.maintenance.replaceSnapshot(snapshot)
//        let report = try? c.rebuildIndex.execute()
//        check(report?.fixes.contains { $0.contains("note") } == true, "rebuild index removes orphaned notes")
//
//        // 12. Typed confirmation
//        check((try? c.deleteAllData.execute(typedConfirmation: "delete")) == false && !c.coins.coins(includeArchived: true).isEmpty, "wrong confirmation text deletes nothing")
//
//        return failures == 0
//    }
//}
//#endif
