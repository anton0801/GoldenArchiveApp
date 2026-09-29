//
//  MaintenanceUseCases.swift
//  GoldenArchive
//
//  Domain layer — backup export, validated import, index rebuild and
//  typed-confirmation deletion.
//

import Foundation

/// A self-contained backup: every record plus every referenced file.
struct BackupPackage: Codable {
    static let format = "golden-archive-backup"

    var format: String = BackupPackage.format
    var exportedAt: Date
    var appVersion: String
    var snapshot: ArchiveSnapshot
    var files: [String: Data]
}

struct ExportBackupUseCase {
    let maintenance: ArchiveMaintenanceRepository
    let media: MediaRepository
    let clock: Clock

    func execute(appVersion: String) throws -> URL {
        let snapshot = maintenance.snapshot()
        var files: [String: Data] = [:]
        for file in snapshot.referencedFiles where files[file.fileName] == nil {
            if let data = media.data(for: file) { files[file.fileName] = data }
        }
        let package = BackupPackage(exportedAt: clock.now, appVersion: appVersion, snapshot: snapshot, files: files)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(package)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GoldenArchive-Backup-\(formatter.string(from: clock.now)).json")
        try data.write(to: url, options: .atomic)
        return url
    }
}

enum ImportMode: String, CaseIterable, Identifiable {
    case merge
    case replace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .merge: return "Add new records"
        case .replace: return "Replace everything"
        }
    }

    var detail: String {
        switch self {
        case .merge: return "Keeps your current archive and adds records from the backup that are not here yet."
        case .replace: return "Your current archive is replaced by the backup after it is written successfully."
        }
    }
}

struct ImportValidation {
    var package: BackupPackage?
    var errors: [String]
    var warnings: [String]
    var counts: [(String, Int)]

    var canImport: Bool { package != nil && errors.isEmpty }
}

struct ValidateImportUseCase {
    func execute(data: Data) -> ImportValidation {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let package: BackupPackage
        do {
            package = try decoder.decode(BackupPackage.self, from: data)
        } catch {
            return ImportValidation(package: nil, errors: ["This file is not a Golden Archive backup or it is damaged."], warnings: [], counts: [])
        }
        var errors: [String] = []
        var warnings: [String] = []
        if package.format != BackupPackage.format { errors.append("Unknown backup format “\(package.format)”.") }
        if package.snapshot.schemaVersion > ArchiveSnapshot.currentSchemaVersion {
            errors.append("The backup was made by a newer version of Golden Archive (schema \(package.snapshot.schemaVersion)).")
        }

        let snapshot = package.snapshot
        let missingFiles = snapshot.referencedFiles.filter { package.files[$0.fileName] == nil }
        if !missingFiles.isEmpty {
            warnings.append("\(missingFiles.count) referenced file\(missingFiles.count == 1 ? " is" : "s are") missing from the backup; those photos or documents will show as unavailable.")
        }
        let unsafeNames = package.files.keys.filter { $0.contains("/") || $0.contains("..") || $0.isEmpty }
        if !unsafeNames.isEmpty { errors.append("The backup contains invalid file names.") }

        let coinIDs = Set(snapshot.coins.map(\.id))
        if coinIDs.count != snapshot.coins.count { errors.append("The backup contains repeated item identifiers.") }
        let collectionIDs = Set(snapshot.collections.map(\.id))
        let danglingCollections = snapshot.coins.filter { $0.collectionID != nil && !collectionIDs.contains($0.collectionID!) }.count
        if danglingCollections > 0 { warnings.append("\(danglingCollections) item(s) point to a missing collection and will be kept as Unsorted.") }
        let danglingSlots = snapshot.sets.flatMap(\.slots).filter { $0.linkedCoinID != nil && !coinIDs.contains($0.linkedCoinID!) }.count
        if danglingSlots > 0 { warnings.append("\(danglingSlots) set slot(s) link to missing items and will be emptied.") }
        let orphanNotes = snapshot.valueNotes.filter { !coinIDs.contains($0.coinID) }.count
            + snapshot.observations.filter { !coinIDs.contains($0.coinID) }.count
        if orphanNotes > 0 { warnings.append("\(orphanNotes) note(s) belong to missing items and will be skipped.") }

        let counts: [(String, Int)] = [
            ("Items", snapshot.coins.count), ("Collections", snapshot.collections.count), ("Sets", snapshot.sets.count),
            ("Condition notes", snapshot.observations.count), ("Documents", snapshot.documents.count),
            ("Wishes", snapshot.wishes.count), ("Goals", snapshot.goals.count), ("Value notes", snapshot.valueNotes.count),
            ("Exhibitions", snapshot.exhibitions.count), ("Files", package.files.count)
        ]
        return ImportValidation(package: package, errors: errors, warnings: warnings, counts: counts)
    }
}

struct ApplyImportUseCase {
    let maintenance: ArchiveMaintenanceRepository
    let media: MediaRepository

    /// Files are written first; the archive is swapped only after every file
    /// was stored. On any failure the current archive is left untouched.
    func execute(_ package: BackupPackage, mode: ImportMode) throws -> Int {
        let current = maintenance.snapshot()
        let existingFiles = media.allStoredFileNames()
        var written: [StoredFile] = []
        var renamed: [String: StoredFile] = [:]
        let incoming = package.snapshot.referencedFiles

        do {
            for file in incoming where renamed[file.fileName] == nil {
                guard let data = package.files[file.fileName] else { continue }
                if mode == .merge && existingFiles.contains(file.fileName) {
                    renamed[file.fileName] = file
                    continue
                }
                let stored = try media.store(data: data, contentType: file.contentType, originalName: file.originalName)
                written.append(stored)
                renamed[file.fileName] = stored
            }
        } catch {
            media.delete(written)
            throw error
        }

        func remap(_ file: StoredFile) -> StoredFile { renamed[file.fileName] ?? file }
        var incomingSnapshot = package.snapshot
        incomingSnapshot.coins = incomingSnapshot.coins.map { coin in
            var copy = coin
            copy.photos = copy.photos.map { photo in
                var p = photo
                p.original = remap(p.original)
                p.cropped = p.cropped.map(remap)
                return p
            }
            return copy
        }
        incomingSnapshot.observations = incomingSnapshot.observations.map { observation in
            var copy = observation
            copy.closeUps = copy.closeUps.map(remap)
            return copy
        }
        incomingSnapshot.documents = incomingSnapshot.documents.map { document in
            var copy = document
            copy.file = copy.file.map(remap)
            if case .uploading = copy.fileState { copy.fileState = .failed(reason: "Interrupted before the backup was made.") }
            return copy
        }

        var result: ArchiveSnapshot
        switch mode {
        case .replace:
            result = incomingSnapshot
            result.settings = current.settings
        case .merge:
            result = current
            func merge<T: Identifiable>(_ existing: [T], _ added: [T]) -> [T] where T.ID == UUID {
                let ids = Set(existing.map(\.id))
                return existing + added.filter { !ids.contains($0.id) }
            }
            result.coins = merge(current.coins, incomingSnapshot.coins)
            result.collections = merge(current.collections, incomingSnapshot.collections)
            result.sets = merge(current.sets, incomingSnapshot.sets)
            result.templates = merge(current.templates, incomingSnapshot.templates)
            result.observations = merge(current.observations, incomingSnapshot.observations)
            result.documents = merge(current.documents, incomingSnapshot.documents)
            result.duplicateGroups = merge(current.duplicateGroups, incomingSnapshot.duplicateGroups)
            result.wishes = merge(current.wishes, incomingSnapshot.wishes)
            result.goals = merge(current.goals, incomingSnapshot.goals)
            result.valueNotes = merge(current.valueNotes, incomingSnapshot.valueNotes)
            result.exhibitions = merge(current.exhibitions, incomingSnapshot.exhibitions)
        }
        result = RebuildIndexUseCase.repairReferences(in: result).snapshot
        result.schemaVersion = ArchiveSnapshot.currentSchemaVersion

        do {
            try maintenance.replaceSnapshot(result)
        } catch {
            media.delete(written)
            throw error
        }
        if mode == .replace {
            let keep = Set(result.referencedFiles.map(\.fileName))
            let stale = media.allStoredFileNames().subtracting(keep)
            media.deleteFiles(named: stale)
        }
        return result.coins.count
    }
}

struct MaintenanceReport {
    var fixes: [String]
    var missingFiles: Int
    var removedOrphanFiles: Int
}

struct RebuildIndexUseCase {
    let maintenance: ArchiveMaintenanceRepository
    let media: MediaRepository

    func execute() throws -> MaintenanceReport {
        let repaired = Self.repairReferences(in: maintenance.snapshot())
        var fixes = repaired.fixes
        if !fixes.isEmpty { try maintenance.replaceSnapshot(repaired.snapshot) }

        let referenced = Set(repaired.snapshot.referencedFiles.map(\.fileName))
        let stored = media.allStoredFileNames()
        let orphans = stored.subtracting(referenced)
        if !orphans.isEmpty {
            media.deleteFiles(named: orphans)
            fixes.append("Removed \(orphans.count) unreferenced file\(orphans.count == 1 ? "" : "s") left by cancelled drafts.")
        }
        let missing = referenced.subtracting(stored).count
        if missing > 0 {
            fixes.append("\(missing) file\(missing == 1 ? " is" : "s are") referenced but missing. The records are kept so you can replace them.")
        }
        return MaintenanceReport(fixes: fixes, missingFiles: missing, removedOrphanFiles: orphans.count)
    }

    /// Clears references to records that no longer exist.
    static func repairReferences(in input: ArchiveSnapshot) -> (snapshot: ArchiveSnapshot, fixes: [String]) {
        var snapshot = input
        var fixes: [String] = []
        let coinIDs = Set(snapshot.coins.map(\.id))
        let collectionIDs = Set(snapshot.collections.map(\.id))

        var count = 0
        for index in snapshot.coins.indices {
            if let id = snapshot.coins[index].collectionID, !collectionIDs.contains(id) {
                snapshot.coins[index].collectionID = nil
                count += 1
            }
        }
        if count > 0 { fixes.append("\(count) item(s) pointed to a missing collection and are now Unsorted.") }

        count = 0
        for setIndex in snapshot.sets.indices {
            if let id = snapshot.sets[setIndex].collectionID, !collectionIDs.contains(id) {
                snapshot.sets[setIndex].collectionID = nil
            }
            for slotIndex in snapshot.sets[setIndex].slots.indices {
                if let id = snapshot.sets[setIndex].slots[slotIndex].linkedCoinID, !coinIDs.contains(id) {
                    snapshot.sets[setIndex].slots[slotIndex].linkedCoinID = nil
                    snapshot.sets[setIndex].slots[slotIndex].linkedAt = nil
                    count += 1
                }
            }
        }
        if count > 0 { fixes.append("Emptied \(count) set slot(s) linked to deleted items.") }

        count = 0
        for index in snapshot.documents.indices {
            let before = snapshot.documents[index].linkedCoinIDs.count
            snapshot.documents[index].linkedCoinIDs.removeAll { !coinIDs.contains($0) }
            count += before - snapshot.documents[index].linkedCoinIDs.count
            if case .uploading = snapshot.documents[index].fileState {
                snapshot.documents[index].fileState = .failed(reason: "The upload was interrupted. Choose the file again.")
                fixes.append("Marked an interrupted upload as failed.")
            }
        }
        if count > 0 { fixes.append("Removed \(count) document link(s) to deleted items.") }

        let observationsBefore = snapshot.observations.count
        snapshot.observations.removeAll { !coinIDs.contains($0.coinID) }
        let notesBefore = snapshot.valueNotes.count
        snapshot.valueNotes.removeAll { !coinIDs.contains($0.coinID) }
        let orphanNotes = observationsBefore - snapshot.observations.count + notesBefore - snapshot.valueNotes.count
        if orphanNotes > 0 { fixes.append("Removed \(orphanNotes) note(s) that belonged to deleted items.") }

        let groupsBefore = snapshot.duplicateGroups.count
        snapshot.duplicateGroups = snapshot.duplicateGroups.compactMap { group in
            var copy = group
            copy.members.removeAll { !coinIDs.contains($0.coinID) }
            return copy.members.count >= 2 ? copy : nil
        }
        if groupsBefore != snapshot.duplicateGroups.count { fixes.append("Closed \(groupsBefore - snapshot.duplicateGroups.count) duplicate group(s) with fewer than two items.") }

        let slotKeys = Set(snapshot.sets.flatMap { set in set.slots.map { SlotReference(setID: set.id, slotID: $0.id) } })
        for index in snapshot.wishes.indices {
            if let slot = snapshot.wishes[index].linkedSlot, !slotKeys.contains(slot) {
                snapshot.wishes[index].linkedSlot = nil
                fixes.append("Unlinked a wish from a removed set slot.")
            }
            if let coinID = snapshot.wishes[index].acquiredCoinID, !coinIDs.contains(coinID) {
                snapshot.wishes[index].acquiredCoinID = nil
            }
        }

        let setIDs = Set(snapshot.sets.map(\.id))
        for index in snapshot.goals.indices {
            switch snapshot.goals[index].target {
            case .completeSets(let ids):
                let kept = ids.filter { setIDs.contains($0) }
                if kept.count != ids.count {
                    snapshot.goals[index].target = .completeSets(kept)
                    fixes.append("Removed deleted sets from a goal.")
                }
            case .itemCount(let collectionID, let target):
                if let collectionID, !collectionIDs.contains(collectionID) {
                    snapshot.goals[index].target = .itemCount(collectionID: nil, target: target)
                    fixes.append("A goal pointed to a deleted collection; it now counts all items.")
                }
            }
        }

        for index in snapshot.exhibitions.indices {
            let before = snapshot.exhibitions[index].items.count
            snapshot.exhibitions[index].items.removeAll { !coinIDs.contains($0.coinID) }
            if before != snapshot.exhibitions[index].items.count { fixes.append("Removed deleted items from an exhibition.") }
        }
        for index in snapshot.collections.indices {
            if let cover = snapshot.collections[index].cover,
               !(snapshot.coins.first { $0.id == cover.coinID }?.photos.contains { $0.id == cover.photoID } ?? false) {
                snapshot.collections[index].cover = nil
                fixes.append("Reset a collection cover whose photo was removed.")
            }
        }
        return (snapshot, fixes)
    }
}

struct DeleteAllDataUseCase {
    static let confirmationPhrase = "DELETE"

    let maintenance: ArchiveMaintenanceRepository
    let media: MediaRepository
    let credentials: CredentialStore

    func execute(typedConfirmation: String) throws -> Bool {
        guard typedConfirmation.trimmed == Self.confirmationPhrase else { return false }
        var fresh = ArchiveSnapshot()
        var settings = AppSettings.default
        settings.hasCompletedOnboarding = true
        fresh.settings = settings
        try maintenance.replaceSnapshot(fresh)
        media.deleteAllFiles()
        credentials.setNumistaAPIKey(nil)
        return true
    }
}
