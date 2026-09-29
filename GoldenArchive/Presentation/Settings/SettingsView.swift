//
//  SettingsView.swift
//  GoldenArchive
//
//  Presentation layer — currency, units, catalog sources, backup, import
//  validation, index rebuild and typed-confirmation deletion.
//

import SwiftUI

@MainActor
final class SettingsViewModel: ArchiveViewModel {
    @Published private(set) var settings: AppSettings
    @Published var apiKey: String
    @Published private(set) var keyTestMessage: String?
    @Published private(set) var isTesting = false

    override init(container: AppContainer) {
        settings = container.settings.settings()
        apiKey = container.credentials.numistaAPIKey() ?? ""
        super.init(container: container)
    }

    override func reload() { settings = container.settings.settings() }

    func update(_ change: (inout AppSettings) -> Void) {
        container.settings.update(change)
        settings = container.settings.settings()
    }

    func saveKey() {
        container.credentials.setNumistaAPIKey(apiKey.trimmed.isEmpty ? nil : apiKey.trimmed)
        keyTestMessage = apiKey.isBlank ? "Key removed." : "Key saved in the Keychain on this device."
    }

    func testCatalog() {
        saveKey()
        isTesting = true
        keyTestMessage = nil
        let catalog = container.catalog
        Task {
            let result = await catalog.search(CatalogQuery(text: "dollar"))
            isTesting = false
            if let error = result.sourceErrors["Numista"] {
                keyTestMessage = "Numista: \(error)"
            } else if result.sourcesQueried.contains("Numista") {
                keyTestMessage = "Numista responded with \(result.candidates.filter { $0.sourceName == "Numista" }.count) results."
            } else {
                keyTestMessage = "Turn Numista on to test it."
            }
        }
    }
}

struct SettingsView: View {
    let container: AppContainer
    @EnvironmentObject private var router: AppRouter
    @StateObject private var model: SettingsViewModel

    @State private var share: ShareItem?
    @State private var exportError: String?
    @State private var importing = false
    @State private var validation: ImportReviewItem?
    @State private var maintenanceReport: MaintenanceReport?
    @State private var showMaintenance = false
    @State private var deleting = false
    @State private var replayOnboarding = false

    private let currencies = ["USD", "EUR", "GBP", "CAD", "AUD", "CHF", "JPY", "CNY", "SEK", "NOK", "DKK", "PLN", "CZK", "RUB", "UAH", "TRY", "INR", "BRL", "MXN", "ZAR", "NZD", "SGD", "HKD", "KRW", "ILS", "AED"]

    init(container: AppContainer) {
        self.container = container
        _model = StateObject(wrappedValue: SettingsViewModel(container: container))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                FormCard(title: "Preferences") {
                    GAMenuPicker(
                        title: "Default currency",
                        selection: Binding(get: { model.settings.defaultCurrency }, set: { value in model.update { $0.defaultCurrency = value } }),
                        options: (currencies.contains(model.settings.defaultCurrency) ? currencies : [model.settings.defaultCurrency] + currencies).map { ($0, $0) }
                    )
                    GAMenuPicker(
                        title: "Units",
                        selection: Binding(get: { model.settings.units }, set: { value in model.update { $0.units = value } }),
                        options: MeasurementUnits.allCases.map { ($0, $0.title) }
                    )
                    Text("Measurements are stored in millimetres and grams and shown in the units you choose.")
                        .font(.caption)
                        .foregroundColor(GAColor.textSecondary)
                }

                FormCard(title: "Catalog sources", footer: "Catalog results are reference suggestions only. The identification is always yours.") {
                    GAToggleRow(
                        title: "Offline reference",
                        subtitle: "A small built-in list of common circulation and bullion types. No network, no images.",
                        isOn: Binding(get: { model.settings.offlineReferenceEnabled }, set: { value in model.update { $0.offlineReferenceEnabled = value } })
                    )
                    Divider()
                    GAToggleRow(
                        title: "Numista",
                        subtitle: "Online catalog. Requires your own free API key from numista.com. Search text is sent to Numista.",
                        isOn: Binding(get: { model.settings.numistaEnabled }, set: { value in model.update { $0.numistaEnabled = value } })
                    )
                    if model.settings.numistaEnabled {
                        VStack(alignment: .leading, spacing: 6) {
                            FieldLabel(title: "API key")
                            SecureField("Paste your Numista API key", text: $model.apiKey)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                                .inputChrome()
                        }
                        GAMenuPicker(
                            title: "Catalog language",
                            selection: Binding(get: { model.settings.catalogLanguage }, set: { value in model.update { $0.catalogLanguage = value } }),
                            options: [("en", "English"), ("fr", "Français"), ("es", "Español")]
                        )
                        HStack(spacing: 10) {
                            Button("Save Key") { model.saveKey() }
                                .buttonStyle(.ga(.quiet, compact: true))
                            Button {
                                model.testCatalog()
                            } label: {
                                if model.isTesting { ProgressView() } else { Text("Test") }
                            }
                            .buttonStyle(.ga(.outline, compact: true))
                        }
                        if let message = model.keyTestMessage {
                            Text(message).font(.caption).foregroundColor(GAColor.textSecondary)
                        }
                    }
                }

                FormCard(title: "Backup & import", footer: "Backups contain your records and files. The catalog API key is never included.") {
                    Button {
                        do {
                            let url = try container.exportBackup.execute(appVersion: container.appVersion)
                            share = ShareItem(items: [url])
                        } catch {
                            exportError = error.localizedDescription
                        }
                    } label: {
                        ActionRowLabel(title: "Export", subtitle: "Create a backup file you can save anywhere", symbol: "square.and.arrow.up", tint: GAColor.navy)
                    }
                    .buttonStyle(.plain)
                    Divider()
                    Button { importing = true } label: {
                        ActionRowLabel(title: "Validate Import", subtitle: "Check a backup before anything is changed", symbol: "square.and.arrow.down", tint: GAColor.navy)
                    }
                    .buttonStyle(.plain)
                    if let exportError { FieldErrorText(message: "Export failed: \(exportError)") }
                }

                FormCard(title: "Maintenance") {
                    Button {
                        do {
                            maintenanceReport = try container.rebuildIndex.execute()
                        } catch {
                            maintenanceReport = MaintenanceReport(fixes: ["The archive could not be updated: \(error.localizedDescription)"], missingFiles: 0, removedOrphanFiles: 0)
                        }
                        showMaintenance = true
                    } label: {
                        ActionRowLabel(title: "Rebuild Index", subtitle: "Repair links to deleted records and clean unused files", symbol: "wrench.and.screwdriver", tint: GAColor.navy)
                    }
                    .buttonStyle(.plain)
                    Divider()
                    Button { replayOnboarding = true } label: {
                        ActionRowLabel(title: "Show Introduction Again", subtitle: nil, symbol: "sparkles", tint: GAColor.bronze)
                    }
                    .buttonStyle(.plain)
                }

                FormCard(title: "Danger zone") {
                    Button { deleting = true } label: {
                        ActionRowLabel(title: "Delete All Data", subtitle: "Removes every record and file from this device", symbol: "trash.fill", tint: GAColor.danger)
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 6) {
                    Text("Golden Archive \(container.appVersion)")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(GAColor.textSecondary)
                    Text("A personal catalog. It does not authenticate items, appraise them, or buy and sell anything. All data stays on this device unless you export it.")
                        .font(.caption)
                        .foregroundColor(GAColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 4)
            }
            .padding(GATheme.gutter)
            .padding(.bottom, 24)
        }
        .gaBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $share) { item in ShareSheet(items: item.items).ignoresSafeArea() }
        .sheet(isPresented: $importing) {
            DocumentFilePicker(types: [.json]) { url in
                importing = false
                guard let url else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let data = (try? Data(contentsOf: url)) ?? Data()
                validation = ImportReviewItem(validation: container.validateImport.execute(data: data), fileName: url.lastPathComponent)
            }
            .ignoresSafeArea()
        }
        .sheet(item: $validation) { item in
            ImportReviewSheet(container: container, item: item)
                .environmentObject(router)
        }
        .sheet(isPresented: $deleting) {
            DeleteAllDataSheet(container: container)
                .environmentObject(router)
        }
        .alert("Rebuild Index", isPresented: $showMaintenance) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(maintenanceReport.map { $0.fixes.isEmpty ? "Everything is consistent. Nothing needed fixing." : $0.fixes.joined(separator: "\n") } ?? "")
        }
        .confirmationDialog("Show the introduction again?", isPresented: $replayOnboarding, titleVisibility: .visible) {
            Button("Show Introduction") { model.update { $0.hasCompletedOnboarding = false } }
        } message: {
            Text("Your data is not changed.")
        }
    }
}

struct ImportReviewItem: Identifiable {
    let id = UUID()
    var validation: ImportValidation
    var fileName: String
}

struct ImportReviewSheet: View {
    let container: AppContainer
    let item: ImportReviewItem
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: AppRouter
    @State private var mode: ImportMode = .merge
    @State private var confirmReplace = false
    @State private var failure: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(item.fileName).font(.headline).foregroundColor(GAColor.text)
                    if item.validation.canImport {
                        Label("The backup is valid.", systemImage: "checkmark.seal.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(GAColor.successText)
                    }
                    ForEach(item.validation.errors, id: \.self) { WarningNote(text: $0, symbol: "xmark.octagon.fill") }
                    ForEach(item.validation.warnings, id: \.self) { InfoNote(text: $0, symbol: "exclamationmark.circle") }
                    if !item.validation.counts.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(item.validation.counts, id: \.0) { row in KeyValueRow(label: row.0, value: "\(row.1)") }
                        }
                        .gaCard()
                    }
                    if item.validation.canImport {
                        FormCard(title: "How to import") {
                            ForEach(ImportMode.allCases) { option in
                                Button { mode = option } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: mode == option ? "largecircle.fill.circle" : "circle")
                                            .foregroundColor(mode == option ? GAColor.navy : GAColor.textTertiary)
                                            .font(.title3)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(option.title).font(.body.weight(.semibold)).foregroundColor(GAColor.text)
                                            Text(option.detail).font(.footnote).foregroundColor(GAColor.textSecondary)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if let failure { WarningNote(text: failure) }
                        Button("Import") {
                            if mode == .replace { confirmReplace = true } else { apply() }
                        }
                        .buttonStyle(.gaPrimary)
                    } else {
                        Text("Nothing was changed. Your current archive is untouched.")
                            .font(.footnote)
                            .foregroundColor(GAColor.textSecondary)
                    }
                }
                .padding(GATheme.gutter)
            }
            .gaBackground()
            .navigationTitle("Validate Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .confirmationDialog("Replace your whole archive?", isPresented: $confirmReplace, titleVisibility: .visible) {
                Button("Replace Everything", role: .destructive) { apply() }
            } message: {
                Text("Current records and files are replaced by the backup. Export a backup first if you might need them.")
            }
        }
        .navigationViewStyle(.stack)
    }

    private func apply() {
        guard let package = item.validation.package else { return }
        do {
            let count = try container.applyImport.execute(package, mode: mode)
            router.show("Import complete — \(GAFormat.count(count, "item")) in archive", symbol: "square.and.arrow.down.fill")
            dismiss()
        } catch {
            failure = "Import failed and nothing was changed. \(error.localizedDescription)"
        }
    }
}

struct DeleteAllDataSheet: View {
    let container: AppContainer
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: AppRouter
    @State private var typed = ""
    @State private var failure: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Delete all data?")
                        .font(GAFont.title(.title2))
                        .foregroundColor(GAColor.text)
                    Text("Every item, collection, set, document, photo, note and exhibition on this device will be permanently removed, together with the saved catalog API key. This cannot be undone.")
                        .font(.subheadline)
                        .foregroundColor(GAColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    InfoNote(text: "Consider exporting a backup first from Settings → Export.")
                    GATextField(title: "Type \(DeleteAllDataUseCase.confirmationPhrase) to confirm", text: $typed, prompt: DeleteAllDataUseCase.confirmationPhrase, capitalization: .characters)
                    if let failure { WarningNote(text: failure) }
                    Button("Delete All Data") {
                        do {
                            if try container.deleteAllData.execute(typedConfirmation: typed) {
                                ThumbnailCache.shared.clear()
                                router.show("All data deleted", symbol: "trash.fill")
                                dismiss()
                            }
                        } catch {
                            failure = "Nothing was deleted: \(error.localizedDescription)"
                        }
                    }
                    .buttonStyle(.gaDestructive)
                    .disabled(typed.trimmed != DeleteAllDataUseCase.confirmationPhrase)
                }
                .padding(GATheme.gutter)
            }
            .gaBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .navigationViewStyle(.stack)
    }
}
