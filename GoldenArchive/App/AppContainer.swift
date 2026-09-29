//
//  AppContainer.swift
//  GoldenArchive
//
//  App layer — the composition root. Concrete data-layer types are chosen
//  here and nowhere else; presentation only sees domain protocols and
//  use cases.
//

import Foundation
import Combine

final class AppContainer: ObservableObject {

    let clock: Clock

    // Repositories
    let changes: ArchiveChangeObserving
    let coins: CoinRepository
    let collections: CollectionRepository
    let sets: SetRepository
    let conditions: ConditionRepository
    let documents: DocumentRepository
    let duplicates: DuplicateRepository
    let wishes: WishRepository
    let goals: GoalRepository
    let valueNotes: ValueNoteRepository
    let exhibitions: ExhibitionRepository
    let settings: SettingsRepository
    let credentials: CredentialStore
    let media: MediaRepository
    let catalog: CatalogRepository
    let maintenance: ArchiveMaintenanceRepository

    // Services
    let exporter: ExhibitionExporting
    let photoProcessor: PhotoProcessing

    private let database: ArchiveDatabase

    init(inMemory: Bool = false) {
        let directory: URL? = inMemory
            ? FileManager.default.temporaryDirectory.appendingPathComponent("GoldenArchive-\(UUID().uuidString)")
            : nil
        let database = ArchiveDatabase(directory: directory)
        let vault = FileVault(directory: directory?.appendingPathComponent("Files"))
        let credentials = KeychainCredentialStore()
        let settings = LocalSettingsRepository(db: database)

        self.database = database
        self.clock = SystemClock()
        self.changes = LocalChangeObserver(db: database)
        self.coins = LocalCoinRepository(db: database)
        self.collections = LocalCollectionRepository(db: database)
        self.sets = LocalSetRepository(db: database)
        self.conditions = LocalConditionRepository(db: database)
        self.documents = LocalDocumentRepository(db: database)
        self.duplicates = LocalDuplicateRepository(db: database)
        self.wishes = LocalWishRepository(db: database)
        self.goals = LocalGoalRepository(db: database)
        self.valueNotes = LocalValueNoteRepository(db: database)
        self.exhibitions = LocalExhibitionRepository(db: database)
        self.settings = settings
        self.credentials = credentials
        self.media = vault
        self.maintenance = LocalMaintenanceRepository(db: database)
        self.catalog = CompositeCatalogRepository(
            offline: OfflineReferenceCatalog(),
            numista: NumistaCatalogSource(client: URLSessionHTTPClient(), apiKey: { credentials.numistaAPIKey() }),
            settings: settings,
            credentials: credentials
        )
        self.exporter = ExhibitionExporter(media: vault)
        self.photoProcessor = DevicePhotoProcessor()
        if !inMemory { MediaURLResolver.media = vault }
    }

    /// Writes pending changes right away (app moving to background).
    func flush() { database.flush() }

    var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: Use cases

    var validator: CoinFormValidator { CoinFormValidator(clock: clock) }

    var linkSlot: LinkCoinToSlotUseCase { LinkCoinToSlotUseCase(coins: coins, sets: sets, clock: clock) }

    var saveCoin: SaveCoinUseCase {
        SaveCoinUseCase(coins: coins, settings: settings, wishes: wishes, linkSlot: linkSlot, validator: validator, clock: clock)
    }

    var coinState: UpdateCoinStateUseCase { UpdateCoinStateUseCase(coins: coins, clock: clock) }

    var deleteCoin: DeleteCoinUseCase {
        DeleteCoinUseCase(coins: coins, collections: collections, sets: sets, documents: documents, conditions: conditions,
                          duplicates: duplicates, valueNotes: valueNotes, exhibitions: exhibitions, wishes: wishes,
                          media: media, clock: clock)
    }

    var photoIntake: PhotoIntakeUseCase { PhotoIntakeUseCase(media: media, processor: photoProcessor, clock: clock) }
    var collectionUseCase: CollectionUseCase { CollectionUseCase(collections: collections, coins: coins, sets: sets, goals: goals, clock: clock) }
    var setEditing: SetEditingUseCase { SetEditingUseCase(sets: sets, wishes: wishes, clock: clock) }
    var duplicateUseCase: DuplicateUseCase { DuplicateUseCase(duplicates: duplicates, coins: coins, clock: clock) }
    var searchCatalog: SearchCatalogUseCase { SearchCatalogUseCase(catalog: catalog) }
    var conditionUseCase: ConditionUseCase { ConditionUseCase(conditions: conditions, media: media, clock: clock) }
    var documentUseCase: DocumentUseCase { DocumentUseCase(documents: documents, media: media, clock: clock) }
    var wishUseCase: WishUseCase { WishUseCase(wishes: wishes, clock: clock) }
    var goalUseCase: GoalUseCase { GoalUseCase(goals: goals, clock: clock) }
    var valueNoteUseCase: ValueNoteUseCase { ValueNoteUseCase(valueNotes: valueNotes, clock: clock) }
    var exhibitionUseCase: ExhibitionUseCase { ExhibitionUseCase(exhibitions: exhibitions, clock: clock) }

    var homeSummary: BuildHomeSummaryUseCase {
        BuildHomeSummaryUseCase(coins: coins, collections: collections, sets: sets, duplicates: duplicates, wishes: wishes)
    }

    var buildReport: BuildReportUseCase {
        BuildReportUseCase(coins: coins, sets: sets, duplicates: duplicates, valueNotes: valueNotes, clock: clock)
    }

    var exportBackup: ExportBackupUseCase { ExportBackupUseCase(maintenance: maintenance, media: media, clock: clock) }
    var validateImport: ValidateImportUseCase { ValidateImportUseCase() }
    var applyImport: ApplyImportUseCase { ApplyImportUseCase(maintenance: maintenance, media: media) }
    var rebuildIndex: RebuildIndexUseCase { RebuildIndexUseCase(maintenance: maintenance, media: media) }
    var deleteAllData: DeleteAllDataUseCase { DeleteAllDataUseCase(maintenance: maintenance, media: media, credentials: credentials) }
}
