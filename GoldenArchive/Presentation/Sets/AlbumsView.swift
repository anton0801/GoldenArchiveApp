//
//  AlbumsView.swift
//  GoldenArchive
//
//  Presentation layer — albums and sets, plus creating a set from scratch
//  or from a template.
//

import SwiftUI

@MainActor
final class AlbumsViewModel: ArchiveViewModel {
    @Published private(set) var sets: [SetSummary] = []
    @Published private(set) var templates: [SetTemplate] = []

    override init(container: AppContainer) {
        super.init(container: container)
        reload()
    }

    override func reload() {
        let calculator = SetProgressCalculator(
            coins: container.coins.coins(includeArchived: true),
            sets: container.sets.sets(includeArchived: true),
            groups: container.duplicates.groups()
        )
        sets = container.sets.sets(includeArchived: false)
            .map { SetSummary(set: $0, progress: calculator.progress(for: $0)) }
            .sorted { $0.set.updatedAt > $1.set.updatedAt }
        templates = container.sets.userTemplates()
    }

    func deleteTemplate(_ id: UUID) { container.sets.deleteTemplate(id: id) }
}

struct AlbumsView: View {
    let container: AppContainer
    var isRoot = true
    @EnvironmentObject private var router: AppRouter
    @StateObject private var model: AlbumsViewModel
    @State private var creating = false

    init(container: AppContainer, isRoot: Bool = true) {
        self.container = container
        self.isRoot = isRoot
        _model = StateObject(wrappedValue: AlbumsViewModel(container: container))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.sets.isEmpty {
                    EmptyStateView(
                        artwork: .album,
                        artSize: CGSize(width: 150, height: 120),
                        title: "No sets yet",
                        message: "A set lists the positions you want — from a template like the 50 State Quarters or your own slots. Link real items to see what is collected and what is missing.",
                        actionTitle: "Create Set",
                        action: { creating = true }
                    )
                } else {
                    header
                    ForEach(model.sets) { item in
                        NavigationLink(destination: SetBuilderView(container: container, setID: item.set.id)) {
                            SetProgressCard(name: item.set.name, progress: item.progress)
                        }
                        .buttonStyle(PressableCardStyle())
                    }
                }
                if !model.templates.isEmpty {
                    SectionHeader(title: "Your Templates", subtitle: "Saved from sets; use them when creating a new set")
                    VStack(spacing: 0) {
                        ForEach(model.templates) { template in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.name).font(.body.weight(.semibold)).foregroundColor(GAColor.text)
                                    Text(template.summary).font(.caption).foregroundColor(GAColor.textSecondary)
                                }
                                Spacer()
                                Button(role: .destructive) { model.deleteTemplate(template.id) } label: {
                                    Image(systemName: "trash").foregroundColor(GAColor.danger).frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("Delete template \(template.name)")
                            }
                            .padding(.vertical, 4)
                            if template.id != model.templates.last?.id { Divider() }
                        }
                    }
                    .gaCard(padding: 12)
                }
            }
            .padding(GATheme.gutter)
            .padding(.bottom, 24)
        }
        .gaBackground()
        .navigationTitle("Albums")
        .navigationBarTitleDisplayMode(isRoot ? .large : .inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { creating = true } label: {
                    Image(systemName: "plus.circle.fill").font(.title3).frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Create set")
            }
        }
        .sheet(isPresented: $creating) {
            NewSetSheet(container: container, presetCollectionID: nil)
                .environmentObject(router)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ArtworkView(artwork: .album)
                .frame(width: 150, height: 120)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text("\(model.sets.count) set\(model.sets.count == 1 ? "" : "s")")
                    .font(GAFont.title(.title3))
                    .foregroundColor(GAColor.text)
                Text("\(model.sets.filter { $0.progress.isComplete }.count) complete")
                    .font(.footnote)
                    .foregroundColor(GAColor.textSecondary)
                Button("New Set") { creating = true }
                    .buttonStyle(.ga(.primary, compact: true, fullWidth: false))
            }
        }
    }
}

// MARK: - New set

struct NewSetSheet: View {
    let container: AppContainer
    let presetCollectionID: UUID?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: AppRouter

    @State private var name = ""
    @State private var collectionID: UUID?
    @State private var note = ""
    @State private var templateID: UUID?
    @State private var country = ""
    @State private var yearText = ""
    @State private var showNameError = false

    init(container: AppContainer, presetCollectionID: UUID?) {
        self.container = container
        self.presetCollectionID = presetCollectionID
        _collectionID = State(initialValue: presetCollectionID)
    }

    private var templates: [SetTemplate] { BuiltInTemplates.all + container.sets.userTemplates() }
    private var selectedTemplate: SetTemplate? { templates.first { $0.id == templateID } }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    FormCard {
                        GATextField(title: "Set name", text: $name, prompt: "e.g. Canada cents 1950s", required: true, capitalization: .words,
                                    error: showNameError ? "Give the set a name." : nil)
                        GAMenuPicker(
                            title: "Collection",
                            selection: $collectionID,
                            options: [(nil, "None")] + container.collections.collections(includeArchived: false).map { (Optional($0.id), $0.name) }
                        )
                        GATextArea(title: "Note", text: $note, prompt: "What the set is for", minHeight: 60)
                    }

                    FormCard(title: "Start from") {
                        templateRow(nil, "Empty set", "Add your own slots one by one.")
                        ForEach(templates) { template in
                            templateRow(template.id, template.name, "\(template.slots.count) slots · \(template.summary)")
                        }
                    }

                    if selectedTemplate != nil {
                        FormCard(title: "Fill every slot with", footer: "Optional. Only blank expectations are filled; you can edit any slot later.") {
                            GATextField(title: "Country", text: $country, prompt: "e.g. Germany", capitalization: .words)
                            GATextField(title: "Year", text: $yearText, prompt: "e.g. 2002", keyboard: .numberPad)
                        }
                    }
                }
                .padding(GATheme.gutter)
            }
            .gaBackground()
            .navigationTitle("New Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Create") { create() }.font(.headline) }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func templateRow(_ id: UUID?, _ title: String, _ subtitle: String) -> some View {
        Button {
            templateID = id
            if name.isBlank, let id, let template = templates.first(where: { $0.id == id }) { name = template.name }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: templateID == id ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundColor(templateID == id ? GAColor.navy : GAColor.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundColor(GAColor.text)
                    Text(subtitle).font(.caption).foregroundColor(GAColor.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func create() {
        guard !name.isBlank else {
            showNameError = true
            return
        }
        let slots = selectedTemplate.map { SetEditingUseCase.slots(from: $0, country: country, year: Int(yearText.trimmed)) } ?? []
        container.setEditing.createSet(name: name, collectionID: collectionID, note: note, slots: slots, templateName: selectedTemplate?.name)
        router.show("Set created")
        dismiss()
    }
}
