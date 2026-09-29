//
//  CoinEditorFields.swift
//  GoldenArchive
//
//  Presentation layer — every attribute of an item, validated inline.
//  Used by Review & Save and by Edit on Coin Details.
//

import SwiftUI

struct CoinEditorFields: View {
    @Binding var form: CoinForm
    var errors: [FieldError]
    var collections: [CoinCollection]
    var units: MeasurementUnits
    var showsReviewToggle = true

    var body: some View {
        VStack(spacing: 16) {
            FormCard(title: "Identity") {
                Picker("Type", selection: $form.kind) {
                    ForEach(ItemKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Item type")
                GATextField(title: "Name", text: $form.name, prompt: "e.g. Peace Dollar 1922", required: true, capitalization: .words, error: errors.message(for: .name))
                GATextField(title: "Country", text: $form.country, prompt: "Issuing country or authority", capitalization: .words)
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        GATextField(title: "Year", text: $form.yearText, prompt: "1922", keyboard: .numberPad, error: errors.message(for: .year))
                        Toggle("BC", isOn: $form.isBC)
                            .font(.caption.weight(.semibold))
                            .tint(GAColor.navy)
                            .fixedSize()
                    }
                    .frame(width: 118)
                    GATextField(title: "Denomination", text: $form.denomination, prompt: form.kind == .coin ? "e.g. 1 dollar" : "If any")
                }
                GATextField(title: "Mint / mint mark", text: $form.mint, prompt: "e.g. Philadelphia, S", capitalization: .words)
            }

            FormCard(title: "Physical", footer: "Numbers accept a comma or a dot. Units follow Settings (\(units.title.lowercased())).") {
                GATextField(title: "Material", text: $form.material, prompt: "e.g. Silver .900", capitalization: .sentences)
                HStack(alignment: .top, spacing: 10) {
                    GATextField(title: "Diameter", text: $form.diameterText, prompt: "38.1", keyboard: .decimalPad, unit: units.diameterUnit, error: errors.message(for: .diameter))
                    GATextField(title: "Weight", text: $form.weightText, prompt: "26.73", keyboard: .decimalPad, unit: units.weightUnit, error: errors.message(for: .weight))
                }
                GATextField(title: "Edge", text: $form.edge, prompt: "e.g. Reeded, plain, lettered")
            }

            FormCard(title: "In your archive") {
                QuantityStepper(value: $form.quantity, error: errors.message(for: .quantity))
                GAMenuPicker(
                    title: "Collection",
                    selection: $form.collectionID,
                    options: [(nil, "Unsorted")] + collections.map { (Optional($0.id), $0.name) }
                )
                GATextField(title: "Condition (your own words)", text: $form.condition, prompt: "e.g. light wear on high points")
                Text("This is your note, not a professional grade. Detailed observations live in Condition Notes.")
                    .font(.caption)
                    .foregroundColor(GAColor.textSecondary)
                GATextArea(title: "Notes", text: $form.notes, prompt: "Anything worth remembering", minHeight: 80)
                TagEditor(tags: $form.tags)
            }

            if showsReviewToggle {
                FormCard(title: "Review") {
                    GAToggleRow(title: "Needs review", subtitle: "Keeps the item in Needs Review on Home until you mark it reviewed.", isOn: $form.needsReview)
                    if form.needsReview {
                        GATextField(title: "Reason", text: $form.reviewReason, prompt: "e.g. check mint mark under a loupe")
                    }
                }
            }
        }
    }
}

/// Edits an existing item. Photos are managed separately on Coin Details.
struct CoinEditSheet: View {
    let container: AppContainer
    let coin: Coin
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: AppRouter
    @State private var form: CoinForm
    @State private var errors: [FieldError] = []

    init(container: AppContainer, coin: Coin) {
        self.container = container
        self.coin = coin
        _form = State(initialValue: CoinForm(coin: coin, units: container.settings.settings().units))
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    if !errors.isEmpty {
                        WarningNote(text: "Please fix the highlighted fields.")
                    }
                    CoinEditorFields(
                        form: $form,
                        errors: errors,
                        collections: container.collections.collections(includeArchived: false),
                        units: container.settings.settings().units
                    )
                }
                .padding(GATheme.gutter)
            }
            .gaBackground()
            .navigationTitle("Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.font(.headline)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func save() {
        hideKeyboard()
        let request = SaveCoinRequest(coinID: coin.id, form: form, photos: coin.photos, catalogReference: nil, pendingSlot: nil, fulfilledWishID: nil)
        switch container.saveCoin.execute(request) {
        case .success:
            router.show("Changes saved")
            dismiss()
        case .failure(let failure):
            errors = failure.errors
        }
    }
}
