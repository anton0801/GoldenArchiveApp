//
//  ConditionNotesView.swift
//  GoldenArchive
//
//  Presentation layer — the user's own dated observations. The app does
//  not assign grades, issue certificates or recommend cleaning.
//

import SwiftUI

@MainActor
final class ConditionNotesViewModel: ArchiveViewModel {
    let coinID: UUID
    @Published private(set) var coin: Coin?
    @Published private(set) var observations: [ConditionObservation] = []

    init(container: AppContainer, coinID: UUID) {
        self.coinID = coinID
        super.init(container: container)
        reload()
    }

    override func reload() {
        coin = container.coins.coin(id: coinID)
        observations = container.conditions.observations(coinID: coinID)
    }

    func delete(_ id: UUID) { container.conditionUseCase.delete(id: id) }
}

struct ConditionNotesView: View {
    let container: AppContainer
    @StateObject private var model: ConditionNotesViewModel
    @State private var editing: EditingObservation?
    @State private var comparing = false
    @State private var compareSelection: [UUID] = []
    @State private var deleting: ConditionObservation?
    @State private var viewing: StoredFile?

    struct EditingObservation: Identifiable {
        let id = UUID()
        var observation: ConditionObservation?
    }

    init(container: AppContainer, coinID: UUID) {
        self.container = container
        _model = StateObject(wrappedValue: ConditionNotesViewModel(container: container, coinID: coinID))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    ArtworkView(artwork: .certificateShield)
                        .frame(width: 140, height: 120)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your observations")
                            .font(GAFont.title(.title3))
                            .foregroundColor(GAColor.text)
                        Text("Record what you see, in your words. These notes are not a professional grade or a certificate, and the app never suggests cleaning a coin.")
                            .font(.footnote)
                            .foregroundColor(GAColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 10) {
                    Button { editing = EditingObservation(observation: nil) } label: { Label("Add Observation", systemImage: "plus") }
                        .buttonStyle(.ga(.primary, compact: true))
                    if model.observations.count > 1 {
                        Button { comparing.toggle(); compareSelection = [] } label: {
                            Label(comparing ? "Cancel" : "Compare Dates", systemImage: "arrow.left.arrow.right")
                        }
                        .buttonStyle(.ga(.outline, compact: true))
                    }
                }

                if comparing {
                    InfoNote(text: "Select two observations to compare them side by side.")
                }

                if model.observations.isEmpty {
                    EmptyStateView(title: "No observations yet", message: "Add a dated note about wear, scratches, color or anything you notice. Attach close-ups from your camera or library.")
                } else {
                    ForEach(model.observations) { observation in
                        observationCard(observation)
                    }
                }
            }
            .padding(GATheme.gutter)
            .padding(.bottom, 24)
        }
        .gaBackground()
        .navigationTitle(model.coin.map { "Condition · \($0.displayName)" } ?? "Condition Notes")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { item in
            ObservationEditorSheet(container: container, coinID: model.coinID, observation: item.observation)
        }
        .sheet(isPresented: Binding(get: { compareSelection.count == 2 }, set: { if !$0 { compareSelection = []; comparing = false } })) {
            let pair = compareSelection.compactMap { id in model.observations.first { $0.id == id } }.sorted { $0.observedOn < $1.observedOn }
            if pair.count == 2 {
                CompareObservationsView(earlier: pair[0], later: pair[1])
                    .environmentObject(container)
            }
        }
        .confirmationDialog("Delete this observation?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete Observation", role: .destructive) {
                if let deleting { model.delete(deleting.id) }
                deleting = nil
            }
        } message: {
            Text("Its close-up photos are deleted too.")
        }
        .fullScreenCover(item: Binding(get: { viewing.map { IdentifiedFile(file: $0) } }, set: { viewing = $0?.file })) { item in
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                StoredImageView(file: item.file, maxPixel: 1400, contentMode: .fit)
                Button("Close") { viewing = nil }.foregroundColor(GAColor.gold).padding()
            }
            .environmentObject(container)
        }
    }

    private func observationCard(_ observation: ConditionObservation) -> some View {
        let selected = compareSelection.contains(observation.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(GAFormat.day(observation.observedOn))
                        .font(.headline)
                        .foregroundColor(GAColor.text)
                    Text(observation.side.title)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(GAColor.textSecondary)
                }
                Spacer()
                if comparing {
                    Button {
                        if selected { compareSelection.removeAll { $0 == observation.id } }
                        else if compareSelection.count < 2 { compareSelection.append(observation.id) }
                    } label: {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundColor(selected ? GAColor.success : GAColor.textTertiary)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(selected ? "Selected for comparison" : "Select for comparison")
                } else {
                    Menu {
                        Button { editing = EditingObservation(observation: observation) } label: { Label("Edit", systemImage: "pencil") }
                        Button(role: .destructive) { deleting = observation } label: { Label("Delete", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Observation actions")
                }
            }
            HStack(spacing: 6) {
                StatusPill(text: observation.wear.title, tint: GAColor.navy)
                if !observation.userGrade.isBlank { StatusPill(text: "Your grade: \(observation.userGrade)", tint: GAColor.gold) }
            }
            if !observation.scratches.isBlank { KeyValueRow(label: "Scratches", value: observation.scratches) }
            if !observation.color.isBlank { KeyValueRow(label: "Color / toning", value: observation.color) }
            KeyValueRow(label: "Cleaning", value: observation.cleaning.title)
            if !observation.note.isBlank {
                Text(observation.note).font(.subheadline).foregroundColor(GAColor.text).fixedSize(horizontal: false, vertical: true)
            }
            if !observation.closeUps.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(observation.closeUps, id: \.fileName) { file in
                            Button { viewing = file } label: {
                                StoredImageView(file: file, maxPixel: 160)
                                    .frame(width: 70, height: 70)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .accessibilityLabel("Close-up photo")
                        }
                    }
                }
            }
            if let last = observation.revisions.last {
                Text("\(last.summary) \(GAFormat.dateTime(last.date))\(observation.revisions.count > 1 ? " · \(observation.revisions.count) revisions" : "")")
                    .font(.caption2)
                    .foregroundColor(GAColor.textTertiary)
            }
        }
        .gaCard()
        .overlay(RoundedRectangle(cornerRadius: GATheme.cornerRadius).strokeBorder(selected ? GAColor.gold : .clear, lineWidth: 2.5))
    }
}

struct IdentifiedFile: Identifiable {
    var file: StoredFile
    var id: String { file.fileName }
}

struct ObservationEditorSheet: View {
    let container: AppContainer
    let coinID: UUID
    let observation: ConditionObservation?
    @Environment(\.dismiss) private var dismiss

    @State private var draft: ConditionObservation
    @State private var addedFiles: [StoredFile] = []
    @State private var pickingLibrary = false
    @State private var capturing = false
    @State private var errorMessage: String?

    init(container: AppContainer, coinID: UUID, observation: ConditionObservation?) {
        self.container = container
        self.coinID = coinID
        self.observation = observation
        let now = Date()
        _draft = State(initialValue: observation ?? ConditionObservation(coinID: coinID, observedOn: now, createdAt: now, updatedAt: now))
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    FormCard {
                        GADateRow(title: "Date", date: $draft.observedOn)
                        GAMenuPicker(title: "Side", selection: $draft.side, options: ObservationSide.allCases.map { ($0, $0.title) })
                        GAMenuPicker(title: "Wear", selection: $draft.wear, options: WearLevel.allCases.map { ($0, $0.title) })
                        GATextField(title: "Scratches", text: $draft.scratches, prompt: "e.g. fine hairline on obverse field")
                        GATextField(title: "Color / toning", text: $draft.color, prompt: "e.g. light gold toning at rim")
                        GAMenuPicker(title: "Cleaning history, if known", selection: $draft.cleaning, options: CleaningHistory.allCases.map { ($0, $0.title) })
                        GATextField(title: "Your grade (text)", text: $draft.userGrade, prompt: "Your own wording, e.g. “about XF”")
                        GATextArea(title: "Note", text: $draft.note, prompt: "What you observed", minHeight: 80)
                    }
                    FormCard(title: "Close-ups") {
                        if !draft.closeUps.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(draft.closeUps, id: \.fileName) { file in
                                        StoredImageView(file: file, maxPixel: 160)
                                            .frame(width: 70, height: 70)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            .overlay(alignment: .topTrailing) {
                                                Button { removeCloseUp(file) } label: {
                                                    Image(systemName: "xmark.circle.fill").foregroundColor(GAColor.danger).background(Circle().fill(.white))
                                                }
                                                .accessibilityLabel("Remove close-up")
                                            }
                                    }
                                }
                                .padding(.top, 4)
                            }
                        }
                        HStack(spacing: 10) {
                            Button { attachFromCamera() } label: { Label("Attach Close-up", systemImage: "camera") }
                                .buttonStyle(.ga(.secondary, compact: true))
                            Button { pickingLibrary = true } label: { Label("Library", systemImage: "photo") }
                                .buttonStyle(.ga(.outline, compact: true))
                        }
                        if let errorMessage { FieldErrorText(message: errorMessage) }
                    }
                    if let observation, !observation.revisions.isEmpty {
                        FormCard(title: "Revision history") {
                            ForEach(observation.revisions.reversed()) { revision in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(revision.summary).font(.footnote).foregroundColor(GAColor.text)
                                    Text(GAFormat.dateTime(revision.date)).font(.caption2).foregroundColor(GAColor.textSecondary)
                                }
                            }
                        }
                    }
                }
                .padding(GATheme.gutter)
            }
            .gaBackground()
            .navigationTitle(observation == nil ? "Add Observation" : "Edit Observation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { cancel() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        container.conditionUseCase.save(draft)
                        dismiss()
                    }
                    .font(.headline)
                }
            }
            .sheet(isPresented: $pickingLibrary) {
                PhotoLibraryPicker(selectionLimit: 4) { picked in
                    pickingLibrary = false
                    picked.forEach { store($0.data, $0.contentType) }
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $capturing) {
                CameraCaptureView(container: container, side: .detail, onUse: { data, type in
                    store(data, type)
                    capturing = false
                }, onCancel: { capturing = false })
            }
        }
        .navigationViewStyle(.stack)
        .interactiveDismissDisabled(!addedFiles.isEmpty)
    }

    private func attachFromCamera() {
        switch CameraPermission.state {
        case .authorized: capturing = true
        case .notDetermined: CameraPermission.request { if $0 { capturing = true } else { errorMessage = "Camera is off. Use Library instead." } }
        case .denied: errorMessage = "Camera access is off in Settings. Use Library instead."
        case .unavailable: errorMessage = "No camera on this device. Use Library instead."
        }
    }

    private func store(_ data: Data, _ type: String) {
        do {
            let file = try container.media.store(data: data, contentType: type, originalName: nil)
            addedFiles.append(file)
            draft.closeUps.append(file)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeCloseUp(_ file: StoredFile) {
        draft.closeUps.removeAll { $0 == file }
        if addedFiles.contains(file) {
            container.media.delete(file)
            addedFiles.removeAll { $0 == file }
        }
    }

    /// Files attached during this edit are removed if the edit is cancelled.
    private func cancel() {
        container.media.delete(addedFiles)
        dismiss()
    }
}

struct CompareObservationsView: View {
    let earlier: ConditionObservation
    let later: ConditionObservation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    HStack {
                        Text("").frame(width: 90)
                        Text(GAFormat.day(earlier.observedOn)).font(.caption.weight(.heavy)).foregroundColor(GAColor.bronzeText).frame(maxWidth: .infinity, alignment: .leading)
                        Text(GAFormat.day(later.observedOn)).font(.caption.weight(.heavy)).foregroundColor(GAColor.bronzeText).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.bottom, 8)
                    row("Side", earlier.side.title, later.side.title)
                    row("Wear", earlier.wear.title, later.wear.title)
                    row("Scratches", earlier.scratches, later.scratches)
                    row("Color", earlier.color, later.color)
                    row("Cleaning", earlier.cleaning.title, later.cleaning.title)
                    row("Your grade", earlier.userGrade, later.userGrade)
                    row("Note", earlier.note, later.note)
                    HStack(alignment: .top) {
                        Text("Close-ups").font(.footnote.weight(.semibold)).foregroundColor(GAColor.textSecondary).frame(width: 90, alignment: .leading)
                        photos(earlier.closeUps).frame(maxWidth: .infinity, alignment: .leading)
                        photos(later.closeUps).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 8)
                }
                .gaCard(padding: 12)
                .padding(GATheme.gutter)
            }
            .gaBackground()
            .navigationTitle("Compare Dates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .navigationViewStyle(.stack)
    }

    private func row(_ label: String, _ a: String, _ b: String) -> some View {
        let changed = a != b
        return VStack(spacing: 0) {
            Divider()
            HStack(alignment: .top) {
                Text(label).font(.footnote.weight(.semibold)).foregroundColor(GAColor.textSecondary).frame(width: 90, alignment: .leading)
                Text(a.isBlank ? "—" : a).font(.footnote).foregroundColor(GAColor.text).frame(maxWidth: .infinity, alignment: .leading)
                Text(b.isBlank ? "—" : b).font(.footnote.weight(changed ? .bold : .regular))
                    .foregroundColor(changed ? GAColor.emberText : GAColor.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8)
        }
    }

    private func photos(_ files: [StoredFile]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if files.isEmpty { Text("—").font(.footnote) }
            ForEach(files.prefix(3), id: \.fileName) { file in
                StoredImageView(file: file, maxPixel: 200)
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}
