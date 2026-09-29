//
//  ProvenanceViews.swift
//  GoldenArchive
//
//  Presentation layer — receipts, certificates and old records. File
//  states are shown honestly; a certificate is stored as the user's
//  document and the app never vouches for it.
//

import SwiftUI
import PDFKit
import UniformTypeIdentifiers

@MainActor
final class DocumentsViewModel: ArchiveViewModel {
    @Published private(set) var documents: [ProvenanceDocument] = []
    @Published var typeFilter: DocumentType? { didSet { reload() } }
    private var all: [ProvenanceDocument] = []

    override init(container: AppContainer) {
        super.init(container: container)
        reload()
    }

    override func reload() {
        all = container.documents.documents()
        documents = typeFilter.map { type in all.filter { $0.type == type } } ?? all
    }

    var isEmpty: Bool { all.isEmpty }

    /// Copies chosen files to a temporary folder with readable names.
    func exportURLs(for ids: Set<UUID>) -> [URL] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ProvenanceExport-\(UUID().uuidString.prefix(6))")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return all.filter { ids.contains($0.id) }.compactMap { document in
            guard let file = document.file, container.media.exists(file) else { return nil }
            let ext = (file.fileName as NSString).pathExtension
            let safe = document.displayTitle.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
            let target = folder.appendingPathComponent("\(safe).\(ext.isEmpty ? "dat" : ext)")
            try? FileManager.default.removeItem(at: target)
            do {
                try FileManager.default.copyItem(at: container.media.url(for: file), to: target)
                return target
            } catch {
                return nil
            }
        }
    }
}

struct DocumentsView: View {
    let container: AppContainer
    @StateObject private var model: DocumentsViewModel
    @State private var creating = false
    @State private var selecting = false
    @State private var selection = Set<UUID>()
    @State private var share: ShareItem?

    init(container: AppContainer) {
        self.container = container
        _model = StateObject(wrappedValue: DocumentsViewModel(container: container))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if model.isEmpty {
                    VStack(spacing: 14) {
                        ArtworkView(artwork: .certificateShield)
                            .frame(width: 120, height: 100)
                            .accessibilityHidden(true)
                        Text("No provenance documents")
                            .font(GAFont.title(.title3))
                            .foregroundColor(GAColor.text)
                        Text("Keep receipts, certificates, auction records and old notes next to the items they belong to. Files stay on this device.")
                            .font(.subheadline)
                            .foregroundColor(GAColor.textSecondary)
                            .multilineTextAlignment(.center)
                        Button("Upload") { creating = true }
                            .buttonStyle(.ga(.primary, fullWidth: false))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(20)
                    .gaCard()
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ChoiceChip(title: "All", isSelected: model.typeFilter == nil) { model.typeFilter = nil }
                            ForEach(DocumentType.allCases) { type in
                                ChoiceChip(title: type.title, isSelected: model.typeFilter == type, symbol: type.symbolName) { model.typeFilter = type }
                            }
                        }
                    }
                    ForEach(model.documents) { document in
                        if selecting {
                            Button {
                                if selection.contains(document.id) { selection.remove(document.id) } else { selection.insert(document.id) }
                            } label: {
                                HStack {
                                    Image(systemName: selection.contains(document.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundColor(selection.contains(document.id) ? GAColor.success : GAColor.textTertiary)
                                    DocumentRow(document: document)
                                }
                                .gaCard(padding: 12, radius: 16)
                            }
                            .buttonStyle(.plain)
                            .disabled(document.fileState != .available)
                        } else {
                            NavigationLink(destination: DocumentDetailView(container: container, documentID: document.id)) {
                                DocumentRow(document: document).gaCard(padding: 12, radius: 16)
                            }
                            .buttonStyle(PressableCardStyle())
                        }
                    }
                }
            }
            .padding(GATheme.gutter)
            .padding(.bottom, selecting ? 90 : 24)
        }
        .gaBackground()
        .navigationTitle("Provenance")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if !model.isEmpty {
                    Button(selecting ? "Done" : "Select") {
                        selecting.toggle()
                        selection.removeAll()
                    }
                }
                Button { creating = true } label: { Image(systemName: "plus.circle.fill").font(.title3).frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Upload document")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting {
                Button("Export Selected (\(selection.count))") {
                    let urls = model.exportURLs(for: selection)
                    if !urls.isEmpty { share = ShareItem(items: urls) }
                }
                .buttonStyle(.gaPrimary)
                .disabled(selection.isEmpty)
                .padding(.horizontal, GATheme.gutter)
                .padding(.vertical, 10)
                .background(GAColor.cream.opacity(0.97).ignoresSafeArea(edges: .bottom))
            }
        }
        .sheet(isPresented: $creating) {
            DocumentEditorSheet(container: container, documentID: nil, presetCoinIDs: [])
        }
        .sheet(item: $share) { item in ShareSheet(items: item.items).ignoresSafeArea() }
    }
}

struct FileStateBadge: View {
    var state: DocumentFileState

    var body: some View {
        switch state {
        case .none: StatusPill(text: "No file", tint: GAColor.silver)
        case .uploading: StatusPill(text: "Uploading", tint: GAColor.gold, symbol: "arrow.up.circle")
        case .failed: StatusPill(text: "Failed", tint: GAColor.danger, symbol: "exclamationmark.triangle")
        case .available: StatusPill(text: "Available", tint: GAColor.success, symbol: "checkmark")
        }
    }
}

struct DocumentRow: View {
    var document: ProvenanceDocument

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: document.type.symbolName, tint: GAColor.navy, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(document.displayTitle)
                    .font(.body.weight(.semibold))
                    .foregroundColor(GAColor.text)
                    .lineLimit(2)
                Text([document.type.title, document.date.map(GAFormat.day) ?? "", document.linkedCoinIDs.isEmpty ? "" : GAFormat.count(document.linkedCoinIDs.count, "item")]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundColor(GAColor.textSecondary)
                FileStateBadge(state: document.fileState)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Detail

@MainActor
final class DocumentDetailViewModel: ArchiveViewModel {
    let documentID: UUID
    @Published private(set) var document: ProvenanceDocument?
    @Published private(set) var linkedCoins: [Coin] = []

    init(container: AppContainer, documentID: UUID) {
        self.documentID = documentID
        super.init(container: container)
        reload()
    }

    override func reload() {
        document = container.documents.document(id: documentID)
        linkedCoins = document?.linkedCoinIDs.compactMap { container.coins.coin(id: $0) } ?? []
    }

    var fileURL: URL? {
        guard let file = document?.file, document?.fileState == .available, container.media.exists(file) else { return nil }
        return container.media.url(for: file)
    }

    var fileMissing: Bool {
        guard let file = document?.file, document?.fileState == .available else { return false }
        return !container.media.exists(file)
    }

    func replace(with url: URL) {
        let useCase = container.documentUseCase
        let id = documentID
        let type = FileTypes.mimeType(for: url)
        Task { await useCase.attachFile(documentID: id, from: url, contentType: type, originalName: url.lastPathComponent) }
    }

    func replace(with data: Data, type: String, name: String) {
        container.documentUseCase.attachData(documentID: documentID, data: data, contentType: type, originalName: name)
    }

    func delete() { container.documentUseCase.delete(id: documentID) }
}

struct DocumentDetailView: View {
    let container: AppContainer
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: DocumentDetailViewModel
    @State private var editing = false
    @State private var linking = false
    @State private var pickingFile = false
    @State private var scanning = false
    @State private var confirmDelete = false
    @State private var share: ShareItem?

    init(container: AppContainer, documentID: UUID) {
        self.container = container
        _model = StateObject(wrappedValue: DocumentDetailViewModel(container: container, documentID: documentID))
    }

    var body: some View {
        Group {
            if let document = model.document {
                content(document)
            } else {
                EmptyStateView(title: "Document not found", message: "It was deleted.").padding(GATheme.gutter)
            }
        }
        .gaBackground()
        .navigationTitle(model.document?.displayTitle ?? "Document")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if model.document != nil {
                    Button("Edit") { editing = true }
                }
            }
        }
        .sheet(isPresented: $editing) {
            DocumentEditorSheet(container: container, documentID: model.documentID, presetCoinIDs: [])
        }
        .sheet(isPresented: $linking) {
            LinkItemsSheet(container: container, selected: Set(model.document?.linkedCoinIDs ?? [])) { ids in
                container.documentUseCase.link(documentID: model.documentID, coinIDs: ids)
            }
        }
        .sheet(isPresented: $pickingFile) {
            DocumentFilePicker { url in
                pickingFile = false
                if let url { model.replace(with: url) }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $scanning) {
            DocumentScanner { data in
                scanning = false
                if let data { model.replace(with: data, type: "application/pdf", name: "Scan.pdf") }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $share) { item in ShareSheet(items: item.items).ignoresSafeArea() }
        .confirmationDialog("Delete this document?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Document and File", role: .destructive) {
                model.delete()
                router.show("Document deleted", symbol: "trash")
                dismiss()
            }
        } message: {
            Text("The record and its file are removed from this device. Linked items are kept.")
        }
    }

    private func content(_ document: ProvenanceDocument) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                preview(document)

                HStack { FileStateBadge(state: document.fileState); Spacer() }
                if case .failed(let reason) = document.fileState {
                    WarningNote(text: "\(reason) The previous file, if any, was kept. Choose the file again to retry.")
                }
                if model.fileMissing {
                    WarningNote(text: "The file is missing on this device. Replace it to restore the document.")
                }
                if document.type == .certificate {
                    InfoNote(text: "Stored as your document. Golden Archive does not verify certificates or confirm authenticity.", symbol: "rosette")
                }

                VStack(alignment: .leading, spacing: 4) {
                    KeyValueRow(label: "Type", value: document.type.title)
                    KeyValueRow(label: "Date", value: document.date.map(GAFormat.day) ?? "")
                    KeyValueRow(label: "Source / seller", value: document.sourceNote)
                    KeyValueRow(label: "Price paid", value: document.pricePaid.map(GAFormat.money) ?? "", placeholder: "Not recorded")
                    if let file = document.file {
                        KeyValueRow(label: "File", value: "\(file.originalName ?? file.fileName) · \(GAFormat.bytes(file.byteCount))")
                    }
                }
                .gaCard()

                if !document.privateNote.isBlank {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Private note", systemImage: "lock.fill").font(.subheadline.weight(.bold)).foregroundColor(GAColor.text)
                        Text(document.privateNote).font(.subheadline).foregroundColor(GAColor.text)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .gaCard()
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionHeader(title: "Linked Items")
                        Button("Link Items") { linking = true }
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(GAColor.bronzeText)
                    }
                    if model.linkedCoins.isEmpty {
                        Text("Not linked to any item yet.").font(.footnote).foregroundColor(GAColor.textSecondary)
                    }
                    ForEach(model.linkedCoins) { coin in
                        NavigationLink(destination: CoinDetailView(container: container, coinID: coin.id)) {
                            CoinRow(coin: coin)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .gaCard()

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Button { pickingFile = true } label: { Label(document.file == nil ? "Upload" : "Replace File", systemImage: "arrow.up.doc") }
                            .buttonStyle(.ga(.secondary, compact: true))
                            .disabled(document.fileState == .uploading)
                        if DocumentScanner.isAvailable {
                            Button { scanning = true } label: { Label("Scan", systemImage: "doc.viewfinder") }
                                .buttonStyle(.ga(.outline, compact: true))
                                .disabled(document.fileState == .uploading)
                        }
                    }
                    if let url = model.fileURL {
                        Button { share = ShareItem(items: [url]) } label: { Label("Export", systemImage: "square.and.arrow.up") }
                            .buttonStyle(.ga(.quiet, compact: true))
                    }
                    Button("Delete Document", role: .destructive) { confirmDelete = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(GAColor.danger)
                        .frame(minHeight: 44)
                }
            }
            .padding(GATheme.gutter)
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func preview(_ document: ProvenanceDocument) -> some View {
        if let url = model.fileURL, let file = document.file {
            Group {
                if file.isImage {
                    StoredImageView(file: file, maxPixel: 900, contentMode: .fit)
                } else if file.isPDF {
                    PDFPreview(url: url)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.fill").font(.largeTitle).foregroundColor(GAColor.navy)
                        Text(file.originalName ?? "File").font(.footnote).foregroundColor(GAColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(height: 320)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(GAColor.stroke, lineWidth: 1))
        } else if document.fileState == .uploading {
            HStack(spacing: 10) {
                ProgressView().tint(GAColor.navy)
                Text("Copying the file into your archive…").font(.subheadline).foregroundColor(GAColor.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .gaCard()
        }
    }
}

struct PDFPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .white
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url { uiView.document = PDFDocument(url: url) }
    }
}

// MARK: - Editor

struct DocumentEditorSheet: View {
    let container: AppContainer
    let documentID: UUID?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: AppRouter

    @State private var draft: ProvenanceDocument
    @State private var priceText: String
    @State private var currency: String
    @State private var pending: PendingFile?
    @State private var pickingFile = false
    @State private var pickingPhoto = false
    @State private var scanning = false
    @State private var linking = false
    @State private var errors: [String] = []

    enum PendingFile {
        case url(URL)
        case data(Data, type: String, name: String)

        var label: String {
            switch self {
            case .url(let url): return url.lastPathComponent
            case .data(_, _, let name): return name
            }
        }
    }

    init(container: AppContainer, documentID: UUID?, presetCoinIDs: [UUID]) {
        self.container = container
        self.documentID = documentID
        let now = Date()
        let existing = documentID.flatMap { container.documents.document(id: $0) }
        let document = existing ?? ProvenanceDocument(linkedCoinIDs: presetCoinIDs, createdAt: now, updatedAt: now)
        _draft = State(initialValue: document)
        _priceText = State(initialValue: document.pricePaid.map { "\($0.amount)" } ?? "")
        _currency = State(initialValue: document.pricePaid?.currency ?? container.settings.settings().defaultCurrency)
    }

    private var isNew: Bool { documentID == nil }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    if !errors.isEmpty { WarningNote(text: errors.joined(separator: " ")) }
                    FormCard {
                        GAMenuPicker(title: "Document type", selection: $draft.type, options: DocumentType.allCases.map { ($0, $0.title) })
                        GATextField(title: "Title", text: $draft.title, prompt: "e.g. Receipt from coin fair", capitalization: .sentences)
                        GAOptionalDateRow(title: "Document date", date: $draft.date)
                        GATextField(title: "Source / seller note", text: $draft.sourceNote, prompt: "Who issued it or where it came from")
                        HStack(alignment: .top, spacing: 10) {
                            GATextField(title: "Price paid (optional)", text: $priceText, prompt: "0.00", keyboard: .decimalPad)
                            GATextField(title: "Currency", text: $currency, prompt: "USD", capitalization: .characters)
                                .frame(width: 96)
                        }
                        GATextArea(title: "Private note", text: $draft.privateNote, prompt: "Only visible to you", minHeight: 60)
                    }

                    if isNew {
                        FormCard(title: "File") {
                            if let pending {
                                HStack {
                                    Image(systemName: "doc.fill").foregroundColor(GAColor.navy)
                                    Text(pending.label).font(.subheadline).foregroundColor(GAColor.text).lineLimit(1)
                                    Spacer()
                                    Button("Remove") { self.pending = nil }.font(.footnote.weight(.bold)).foregroundColor(GAColor.danger)
                                }
                            }
                            HStack(spacing: 8) {
                                Button { pickingFile = true } label: { Label("Upload", systemImage: "arrow.up.doc") }
                                    .buttonStyle(.ga(.secondary, compact: true))
                                if DocumentScanner.isAvailable {
                                    Button { scanning = true } label: { Label("Scan", systemImage: "doc.viewfinder") }
                                        .buttonStyle(.ga(.outline, compact: true))
                                }
                                Button { pickingPhoto = true } label: { Label("Photo", systemImage: "photo") }
                                    .buttonStyle(.ga(.outline, compact: true))
                            }
                            Text("The file is copied into the app. Its state is shown as Uploading, Available or Failed.")
                                .font(.caption)
                                .foregroundColor(GAColor.textSecondary)
                        }
                    }

                    FormCard(title: "Linked items") {
                        let coins = draft.linkedCoinIDs.compactMap { container.coins.coin(id: $0) }
                        if coins.isEmpty {
                            Text("Not linked yet.").font(.footnote).foregroundColor(GAColor.textSecondary)
                        }
                        ForEach(coins) { coin in CoinRow(coin: coin, showsChevron: false) }
                        Button { linking = true } label: { Label("Link Items", systemImage: "link") }
                            .buttonStyle(.ga(.quiet, compact: true))
                    }
                    if draft.type == .certificate {
                        InfoNote(text: "Certificates are stored as your documents. The app does not check whether they are genuine.", symbol: "rosette")
                    }
                }
                .padding(GATheme.gutter)
            }
            .gaBackground()
            .navigationTitle(isNew ? "Add Document" : "Edit Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.font(.headline) }
            }
            .sheet(isPresented: $pickingFile) {
                DocumentFilePicker { url in
                    pickingFile = false
                    if let url {
                        pending = .url(url)
                        if draft.title.isBlank { draft.title = url.deletingPathExtension().lastPathComponent }
                    }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $pickingPhoto) {
                PhotoLibraryPicker(selectionLimit: 1) { picked in
                    pickingPhoto = false
                    if let first = picked.first {
                        let ext = UTType(mimeType: first.contentType)?.preferredFilenameExtension ?? "jpg"
                        pending = .data(first.data, type: first.contentType, name: "Photo.\(ext)")
                    }
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $scanning) {
                DocumentScanner { data in
                    scanning = false
                    if let data { pending = .data(data, type: "application/pdf", name: "Scan.pdf") }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $linking) {
                LinkItemsSheet(container: container, selected: Set(draft.linkedCoinIDs)) { ids in draft.linkedCoinIDs = ids }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func save() {
        errors = []
        if !priceText.isBlank {
            guard let amount = NumberText.parseDecimal(priceText), amount >= 0 else {
                errors.append("Price must be a number.")
                return
            }
            let code = currency.trimmed.uppercased()
            guard code.count == 3 else {
                errors.append("Use a three-letter currency code.")
                return
            }
            draft.pricePaid = MoneyAmount(amount: amount, currency: code)
        } else {
            draft.pricePaid = nil
        }
        if isNew, pending != nil { draft.fileState = .uploading }
        let useCase = container.documentUseCase
        useCase.save(draft)
        let id = draft.id
        switch pending {
        case .url(let url):
            let type = FileTypes.mimeType(for: url)
            Task { await useCase.attachFile(documentID: id, from: url, contentType: type, originalName: url.lastPathComponent) }
        case .data(let data, let type, let name):
            useCase.attachData(documentID: id, data: data, contentType: type, originalName: name)
        case nil:
            break
        }
        router.show(isNew ? "Document added" : "Document saved", symbol: "doc.fill")
        dismiss()
    }
}

/// Multi-select of items (used for documents and exhibitions).
struct LinkItemsSheet: View {
    let container: AppContainer
    @State var selected: Set<UUID>
    var onDone: ([UUID]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var coins: [Coin] {
        let query = search.normalizedKey
        return container.coins.coins(includeArchived: false)
            .filter { query.isEmpty || $0.searchText.contains(query) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 8) {
                    if coins.isEmpty {
                        EmptyStateView(title: "No items", message: "Add items to your archive first.")
                    }
                    ForEach(coins) { coin in
                        Button {
                            if selected.contains(coin.id) { selected.remove(coin.id) } else { selected.insert(coin.id) }
                        } label: {
                            HStack {
                                Image(systemName: selected.contains(coin.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundColor(selected.contains(coin.id) ? GAColor.success : GAColor.textTertiary)
                                CoinRow(coin: coin, showsChevron: false)
                            }
                            .gaCard(padding: 10, radius: 16)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected.contains(coin.id) ? .isSelected : [])
                    }
                }
                .padding(GATheme.gutter)
            }
            .gaBackground()
            .searchable(text: $search, prompt: "Search items")
            .navigationTitle("Link Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done (\(selected.count))") {
                        let order = container.coins.coins(includeArchived: true).map(\.id)
                        onDone(order.filter { selected.contains($0) })
                        dismiss()
                    }
                    .font(.headline)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
