//
//  AddCoinFlowView.swift
//  GoldenArchive
//
//  Presentation layer — Add Coin → Photo Capture → Identification Review →
//  Review & Save. The record is created only by Save.
//

import SwiftUI

struct AddCoinFlowView: View {
    let container: AppContainer
    @EnvironmentObject private var router: AppRouter
    @StateObject private var model: AddCoinFlowModel
    @State private var confirmDiscard = false
    @State private var creatingCollection = false
    @State private var openSavedItem = false

    init(container: AppContainer, request: AddCoinRequest) {
        self.container = container
        _model = StateObject(wrappedValue: AddCoinFlowModel(container: container, request: request))
    }

    var body: some View {
        NavigationView {
            ZStack {
                ScreenBackground()
                stepView
                    .id(model.current)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
            .animation(.easeInOut(duration: 0.25), value: model.path)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if model.canGoBack {
                        Button {
                            model.back()
                        } label: {
                            Label("Back", systemImage: "chevron.left").labelStyle(.titleAndIcon)
                        }
                    } else if model.current != .saved {
                        Button("Cancel") { cancel() }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if model.canGoBack {
                        Button("Cancel") { cancel() }
                    }
                }
            }
            .background(
                NavigationLink(isActive: $openSavedItem) {
                    if let coin = model.outcome?.coin {
                        CoinDetailView(container: container, coinID: coin.id)
                    }
                } label: { EmptyView() }
            )
        }
        .navigationViewStyle(.stack)
        .interactiveDismissDisabled(model.hasUnsavedWork)
        .confirmationDialog("Discard this draft?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard Draft", role: .destructive) {
                model.discardDraft()
                router.addCoin = nil
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Nothing has been saved yet. Photos taken for this draft will be removed.")
        }
        .sheet(isPresented: $creatingCollection) {
            CollectionEditorSheet(container: container, collection: nil) { created in
                model.refreshCollections()
                if let created { model.form.collectionID = created.id }
            }
            .environmentObject(router)
        }
    }

    private var title: String {
        switch model.current {
        case .start: return "Add Coin"
        case .photos: return "Photos"
        case .identify: return "Identification Review"
        case .review: return "Review & Save"
        case .saved: return "Saved"
        }
    }

    private func cancel() {
        if model.hasUnsavedWork {
            confirmDiscard = true
        } else {
            model.discardDraft()
            router.addCoin = nil
        }
    }

    @ViewBuilder
    private var stepView: some View {
        switch model.current {
        case .start: startStep
        case .photos: photosStep
        case .identify: IdentificationReviewView(model: model)
        case .review: reviewStep
        case .saved: savedStep
        }
    }

    // MARK: Start (Add Coin)

    private var startStep: some View {
        ScrollView {
            VStack(spacing: 18) {
                ArtworkView(artwork: .scanLens)
                    .frame(width: 150, height: 150)
                    .accessibilityHidden(true)
                VStack(spacing: 6) {
                    Text("How would you like to add it?")
                        .font(GAFont.title(.title3))
                        .foregroundColor(GAColor.text)
                    Text("Nothing is saved until you review the details and tap Save.")
                        .font(.footnote)
                        .foregroundColor(GAColor.textSecondary)
                }
                .multilineTextAlignment(.center)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    methodCard("Take Photo", "Obverse, reverse and edge", "camera.fill", .takePhoto)
                    methodCard("Choose Photo", "From your library", "photo.on.rectangle.angled", .choosePhoto)
                    methodCard("Search Catalog", "Reference suggestions", "magnifyingglass", .searchCatalog)
                    methodCard("Enter Manually", "Type the details", "square.and.pencil", .manual)
                }

                FormCard(title: "Where it goes") {
                    HStack(alignment: .bottom, spacing: 8) {
                        GAMenuPicker(
                            title: "Collection",
                            selection: $model.form.collectionID,
                            options: [(nil, "Unsorted")] + model.collections.map { (Optional($0.id), $0.name) }
                        )
                        Button {
                            creatingCollection = true
                        } label: {
                            Image(systemName: "plus").font(.headline).frame(width: 44, height: 44)
                        }
                        .buttonStyle(.ga(.quiet, compact: true, fullWidth: false))
                        .accessibilityLabel("New collection")
                    }
                    QuantityStepper(value: $model.form.quantity)
                    GATextArea(title: "Initial note", text: $model.form.notes, prompt: "Where or when you got it, anything to check later", minHeight: 70)
                }
                if model.request.pendingSlot != nil || model.request.wishID != nil {
                    InfoNote(text: model.request.wishID != nil
                             ? "Saving will mark the wish as acquired and link its set slot, if it has one."
                             : "Saving will link this item to the set slot you started from.")
                }
            }
            .padding(GATheme.gutter)
        }
    }

    private func methodCard(_ title: String, _ subtitle: String, _ symbol: String, _ method: AddMethod) -> some View {
        Button {
            hideKeyboard()
            model.choose(method)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                IconBadge(symbol: symbol, tint: GAColor.gold, size: 42)
                Text(title)
                    .font(.headline)
                    .foregroundColor(GAColor.text)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(GAColor.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .gaCard(padding: 14, radius: 18)
        }
        .buttonStyle(PressableCardStyle())
    }

    // MARK: Photos

    private var photosStep: some View {
        ScrollView {
            VStack(spacing: 16) {
                PhotoSetEditor(container: container, photos: $model.photos, openLibraryOnAppear: $model.openLibraryOnAppear)
            }
            .padding(GATheme.gutter)
            .padding(.bottom, 90)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                Button(model.photos.isEmpty ? "Continue Without Photos" : "Continue") {
                    model.continueFromPhotos()
                }
                .buttonStyle(model.photos.isEmpty ? .ga(.outline) : .gaPrimary)
                Text("Next: compare with reference sources, or skip to manual details.")
                    .font(.caption)
                    .foregroundColor(GAColor.textSecondary)
            }
            .padding(.horizontal, GATheme.gutter)
            .padding(.vertical, 10)
            .background(GAColor.cream.opacity(0.97).ignoresSafeArea(edges: .bottom))
        }
    }

    // MARK: Review & Save

    private var reviewStep: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !model.errors.isEmpty {
                    WarningNote(text: "Please fix the highlighted fields before saving.")
                }
                if !model.photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(model.photos) { photo in
                                VStack(spacing: 4) {
                                    StoredImageView(file: photo.displayFile, maxPixel: 180)
                                        .frame(width: 76, height: 76)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    Text(photo.side.title).font(.caption2).foregroundColor(GAColor.textSecondary)
                                }
                            }
                            Button {
                                model.push(.photos)
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "camera").font(.title3)
                                    Text("Photos").font(.caption2)
                                }
                                .foregroundColor(GAColor.navy)
                                .frame(width: 76, height: 76)
                                .background(RoundedRectangle(cornerRadius: 12).strokeBorder(GAColor.stroke, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                            }
                        }
                    }
                } else {
                    Button {
                        model.push(.photos)
                    } label: {
                        Label("Add Photos", systemImage: "camera")
                    }
                    .buttonStyle(.ga(.quiet))
                }

                if let reference = model.reference {
                    referenceCard(reference)
                }

                CoinEditorFields(form: $model.form, errors: model.errors, collections: model.collections, units: model.units)

                if model.form.country.isBlank || model.form.yearText.isBlank || (model.form.denomination.isBlank && model.form.kind == .coin) {
                    InfoNote(text: "Items saved without country, year or denomination are placed in Needs Review so you can complete them later.")
                }
            }
            .padding(GATheme.gutter)
            .padding(.bottom, 90)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                hideKeyboard()
                model.save()
            } label: {
                if model.isSaving { ProgressView().tint(GAColor.text) } else { Text("Save to Archive") }
            }
            .buttonStyle(.gaPrimary)
            .disabled(model.isSaving || model.outcome != nil)
            .padding(.horizontal, GATheme.gutter)
            .padding(.vertical, 10)
            .background(GAColor.cream.opacity(0.97).ignoresSafeArea(edges: .bottom))
        }
    }

    private func referenceCard(_ reference: CatalogReference) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Reference used", systemImage: "books.vertical")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(GAColor.text)
                Spacer()
                Button("Remove") { model.reference = nil }
                    .font(.footnote.weight(.bold))
                    .foregroundColor(GAColor.danger)
            }
            Text(reference.title).font(.body.weight(.semibold)).foregroundColor(GAColor.text)
            Text("\(reference.sourceName) · \(reference.matchLabel)")
                .font(.footnote)
                .foregroundColor(GAColor.textSecondary)
            Text("Blank fields were filled from the reference. Check each one — you confirm the identification.")
                .font(.caption)
                .foregroundColor(GAColor.textSecondary)
        }
        .gaCard()
    }

    // MARK: Saved

    private var savedStep: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let coin = model.outcome?.coin {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 44))
                            .foregroundColor(GAColor.success)
                        Text("Saved to your archive")
                            .font(GAFont.title(.title2))
                            .foregroundColor(GAColor.text)
                        CoinRow(coin: coin, showsChevron: false)
                            .gaCard(padding: 12)
                        if coin.needsReview {
                            InfoNote(text: "It is listed in Needs Review: \(coin.reviewReason.isBlank ? "marked by you." : coin.reviewReason)", symbol: "exclamationmark.circle")
                        }
                        if let message = model.slotMessage {
                            if model.needsSlotConfirmation {
                                VStack(alignment: .leading, spacing: 10) {
                                    WarningNote(text: message)
                                    Button("Confirm Quantity & Link") { model.confirmSlotQuantity() }
                                        .buttonStyle(.ga(.secondary, compact: true))
                                }
                            } else {
                                InfoNote(text: message, symbol: "link")
                            }
                        }
                    }
                    .padding(.top, 20)

                    VStack(spacing: 10) {
                        Button("Open Item") { openSavedItem = true }
                            .buttonStyle(.gaPrimary)
                        Button("Add Another") { model.startAnother() }
                            .buttonStyle(.gaOutline)
                        Button("Done") { router.addCoin = nil }
                            .buttonStyle(.gaQuiet)
                    }
                }
            }
            .padding(GATheme.gutter)
        }
    }
}
