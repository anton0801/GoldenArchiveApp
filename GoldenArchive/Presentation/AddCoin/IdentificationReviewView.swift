//
//  IdentificationReviewView.swift
//  GoldenArchive
//
//  Presentation layer — reference candidates next to what the user
//  entered. Confidence is metadata agreement only; the user decides.
//  A failing source never blocks manual entry.
//

import SwiftUI

struct IdentificationReviewView: View {
    @ObservedObject var model: AddCoinFlowModel
    @State private var comparing: AssessedCandidate?
    @State private var searchExpanded = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !model.photos.isEmpty { yourPhotos }
                searchCard
                InfoNote(text: "Confidence only describes how well a reference's metadata matches what you entered. It is not an expert identification — you confirm every detail.")
                results
            }
            .padding(GATheme.gutter)
            .padding(.bottom, 110)
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .sheet(item: $comparing) { candidate in
            CandidateCompareView(model: model, candidateID: candidate.id)
        }
        .onAppear {
            if model.searchState == .idle && !model.queryIsEmpty && !model.catalogSources.isEmpty { model.search() }
        }
    }

    private var yourPhotos: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your photos")
                .font(.subheadline.weight(.bold))
                .foregroundColor(GAColor.textSecondary)
            HStack(spacing: 10) {
                ForEach(model.photos.filter { $0.side != .detail }) { photo in
                    VStack(spacing: 4) {
                        StoredImageView(file: photo.displayFile, maxPixel: 160)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Text(photo.side.title).font(.caption2).foregroundColor(GAColor.textSecondary)
                    }
                }
            }
        }
    }

    private var searchCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation { searchExpanded.toggle() }
            } label: {
                HStack {
                    Text("What you can read on the item")
                        .font(GAFont.headline())
                        .foregroundColor(GAColor.text)
                    Spacer()
                    Image(systemName: searchExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(GAColor.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(searchExpanded ? "Collapse search" : "Edit Search")

            if searchExpanded {
                Picker("Type", selection: $model.query.kind) {
                    ForEach(ItemKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                GATextField(title: "Keywords", text: $model.query.text, prompt: "e.g. Morgan, maple leaf, state quarter")
                HStack(alignment: .top, spacing: 10) {
                    GATextField(title: "Country", text: $model.query.country, prompt: "e.g. United States", capitalization: .words)
                    GATextField(title: "Year", text: $model.queryYearText, prompt: "1921", keyboard: .numberPad)
                        .frame(width: 96)
                }
                HStack(alignment: .top, spacing: 10) {
                    GATextField(title: "Denomination", text: $model.query.denomination, prompt: "1 dollar")
                    GATextField(title: "Mint mark", text: $model.query.mint, prompt: "S", capitalization: .characters)
                        .frame(width: 110)
                }
                GATextField(title: "Material", text: $model.query.material, prompt: "Silver")
            } else {
                Text(model.query.attributes.summary.isEmpty ? model.query.text : model.query.attributes.summary)
                    .font(.subheadline)
                    .foregroundColor(GAColor.textSecondary)
            }

            if model.catalogSources.isEmpty {
                WarningNote(text: "All catalog sources are turned off in Settings. You can still continue manually.")
            } else {
                Button {
                    hideKeyboard()
                    searchExpanded = false
                    model.search()
                } label: {
                    Label(model.searchState == .done ? "Search Again" : "Search References", systemImage: "magnifyingglass")
                }
                .buttonStyle(.ga(.secondary))
                .disabled(model.queryIsEmpty || model.searchState == .searching)
                Text("Sources: \(model.catalogSources.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(GAColor.textSecondary)
            }
        }
        .gaCard()
    }

    @ViewBuilder
    private var results: some View {
        switch model.searchState {
        case .idle:
            EmptyStateView(
                artwork: .scanLens,
                artSize: CGSize(width: 110, height: 110),
                title: "Describe it, then search",
                message: "Enter the country, year or denomination you can read. Reference sources suggest possible matches; nothing is decided automatically."
            )
        case .searching:
            HStack(spacing: 12) {
                ProgressView().tint(GAColor.navy)
                Text("Checking \(model.catalogSources.joined(separator: " and "))…")
                    .font(.subheadline)
                    .foregroundColor(GAColor.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .gaCard()
        case .done:
            VStack(alignment: .leading, spacing: 12) {
                ForEach(model.sourceErrors.sorted(by: { $0.key < $1.key }), id: \.key) { source, message in
                    WarningNote(text: "\(source): \(message) Manual entry still works.")
                }
                if model.candidates.isEmpty {
                    EmptyStateView(
                        artwork: .scanLens,
                        artSize: CGSize(width: 110, height: 110),
                        title: "No reference matches",
                        message: "Try fewer or different details, or continue manually — your own description is enough to save the item."
                    )
                } else {
                    SectionHeader(title: "Possible matches", subtitle: "\(model.candidates.count) from \(model.sourcesQueried.joined(separator: ", "))")
                    ForEach(model.candidates) { candidate in
                        CandidateCard(
                            candidate: candidate,
                            isSelected: model.selectedCandidateID == candidate.id,
                            onSelect: { model.selectedCandidateID = model.selectedCandidateID == candidate.id ? nil : candidate.id },
                            onCompare: { comparing = candidate }
                        )
                    }
                }
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if let warning = model.detailWarning {
                Text(warning).font(.caption).foregroundColor(GAColor.emberText)
            }
            HStack(spacing: 10) {
                Button("None Match") { model.noneMatch() }
                    .buttonStyle(.ga(.outline))
                Button {
                    Task { await model.confirmDetails() }
                } label: {
                    if model.isConfirming {
                        ProgressView().tint(GAColor.text)
                    } else {
                        Text("Confirm Details")
                    }
                }
                .buttonStyle(.gaPrimary)
                .disabled(model.selectedCandidateID == nil || model.isConfirming)
            }
        }
        .padding(.horizontal, GATheme.gutter)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(GAColor.cream.opacity(0.97).ignoresSafeArea(edges: .bottom))
        .overlay(Rectangle().fill(GAColor.stroke).frame(height: 1), alignment: .top)
    }
}

struct CandidateCard: View {
    var candidate: AssessedCandidate
    var isSelected: Bool
    var onSelect: () -> Void
    var onCompare: () -> Void

    var body: some View {
        let c = candidate.candidate
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                CandidateImage(candidate: c, size: 76)
                VStack(alignment: .leading, spacing: 4) {
                    Text(c.title)
                        .font(.headline)
                        .foregroundColor(GAColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text([c.country, c.yearRangeText, c.denomination].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundColor(GAColor.textSecondary)
                    if !c.material.isEmpty || !c.mints.isEmpty {
                        Text([c.material, c.mints.isEmpty ? "" : "Mints: \(c.mints.joined(separator: ", "))"].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundColor(GAColor.textSecondary)
                    }
                    StatusPill(text: candidate.assessment.strength.label, tint: strengthTint, symbol: "chart.bar.fill")
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            if !candidate.assessment.differences.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Differences from what you entered")
                        .font(.caption.weight(.bold))
                        .foregroundColor(GAColor.emberText)
                    ForEach(candidate.assessment.differences) { diff in
                        Text("\(diff.field): you entered “\(diff.entered)”, reference says “\(diff.reference)”")
                            .font(.caption)
                            .foregroundColor(GAColor.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else if !candidate.assessment.matchedFields.isEmpty {
                Text("Matches: \(candidate.assessment.matchedFields.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(GAColor.successText)
            }
            Text("Source: \(c.sourceName)")
                .font(.caption2)
                .foregroundColor(GAColor.textTertiary)
            HStack(spacing: 10) {
                Button(action: onSelect) {
                    Label(isSelected ? "Selected" : "Select Candidate", systemImage: isSelected ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.ga(isSelected ? .secondary : .quiet, compact: true))
                Button("Compare", action: onCompare)
                    .buttonStyle(.ga(.outline, compact: true, fullWidth: false))
            }
        }
        .gaCard()
        .overlay(
            RoundedRectangle(cornerRadius: GATheme.cornerRadius, style: .continuous)
                .strokeBorder(isSelected ? GAColor.gold : Color.clear, lineWidth: 2.5)
        )
    }

    private var strengthTint: Color {
        switch candidate.assessment.strength {
        case .strong: return GAColor.success
        case .partial: return GAColor.gold
        case .weak: return GAColor.silver
        }
    }
}

/// A reference image, always labelled with its source.
struct CandidateImage: View {
    var candidate: CatalogCandidate
    var size: CGFloat

    var body: some View {
        VStack(spacing: 3) {
            Group {
                if let url = candidate.imageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFit()
                        case .failure: noImage
                        default: ProgressView().tint(GAColor.navy)
                        }
                    }
                } else {
                    noImage
                }
            }
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(GAColor.stroke, lineWidth: 1))
            Text(candidate.imageURL == nil ? "No image" : (candidate.imageCredit ?? "Image: \(candidate.sourceName)"))
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(GAColor.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: size)
        }
    }

    private var noImage: some View {
        Image(systemName: "photo")
            .foregroundColor(GAColor.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GAColor.silver.opacity(0.4))
    }
}

struct CandidateCompareView: View {
    @ObservedObject var model: AddCoinFlowModel
    let candidateID: String
    @Environment(\.dismiss) private var dismiss
    @State private var loading = false

    private var candidate: AssessedCandidate? { model.candidates.first { $0.id == candidateID } }

    var body: some View {
        NavigationView {
            ScrollView {
                if let candidate {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 14) {
                            VStack(spacing: 6) {
                                Text("Your photo").font(.caption.weight(.bold)).foregroundColor(GAColor.textSecondary)
                                StoredImageView(file: model.photos.first { $0.side == .obverse }?.displayFile ?? model.photos.first?.displayFile, maxPixel: 300)
                                    .frame(width: 130, height: 130)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            VStack(spacing: 6) {
                                Text("Reference").font(.caption.weight(.bold)).foregroundColor(GAColor.textSecondary)
                                CandidateImage(candidate: candidate.candidate, size: 130)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        StatusPill(text: candidate.assessment.strength.label, tint: GAColor.gold)

                        VStack(spacing: 0) {
                            compareHeader
                            compareRow("Country", model.query.country, candidate.candidate.country)
                            compareRow("Year", model.queryYearText, candidate.candidate.yearRangeText)
                            compareRow("Denomination", model.query.denomination, candidate.candidate.denomination)
                            compareRow("Mint mark", model.query.mint, candidate.candidate.mints.joined(separator: ", "))
                            compareRow("Material", model.query.material, candidate.candidate.material)
                            compareRow("Diameter", "", model.units.diameterText(candidate.candidate.diameterMM) ?? "")
                            compareRow("Weight", "", model.units.weightText(candidate.candidate.weightGrams) ?? "")
                            compareRow("Edge", "", candidate.candidate.edge)
                        }
                        .gaCard(padding: 12)

                        if loading {
                            HStack { ProgressView(); Text("Loading details from \(candidate.candidate.sourceName)…").font(.footnote) }
                        }
                        if let warning = model.detailWarning { WarningNote(text: warning) }
                        InfoNote(text: "Reference data comes from \(candidate.candidate.sourceName). Blank fields in your record will be filled from it only after you tap Confirm Details, and you can edit everything before saving.")

                        Button {
                            model.selectedCandidateID = candidateID
                            dismiss()
                        } label: {
                            Text("Select Candidate")
                        }
                        .buttonStyle(.gaPrimary)
                    }
                    .padding(GATheme.gutter)
                }
            }
            .gaBackground()
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .task {
                loading = true
                await model.loadDetails(for: candidateID)
                loading = false
            }
        }
        .navigationViewStyle(.stack)
    }

    private var compareHeader: some View {
        HStack {
            Text("").frame(width: 92, alignment: .leading)
            Text("You entered").font(.caption.weight(.heavy)).foregroundColor(GAColor.bronzeText).frame(maxWidth: .infinity, alignment: .leading)
            Text("Reference").font(.caption.weight(.heavy)).foregroundColor(GAColor.bronzeText).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 6)
    }

    private func compareRow(_ label: String, _ entered: String, _ reference: String) -> some View {
        let differs = !entered.isBlank && !reference.isBlank && entered.normalizedKey != reference.normalizedKey
        return VStack(spacing: 0) {
            Divider()
            HStack(alignment: .top) {
                Text(label).font(.footnote.weight(.semibold)).foregroundColor(GAColor.textSecondary).frame(width: 92, alignment: .leading)
                Text(entered.isBlank ? "—" : entered).font(.footnote).foregroundColor(GAColor.text).frame(maxWidth: .infinity, alignment: .leading)
                Text(reference.isBlank ? "—" : reference)
                    .font(.footnote.weight(differs ? .bold : .regular))
                    .foregroundColor(differs ? GAColor.emberText : GAColor.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8)
        }
        .accessibilityElement(children: .combine)
    }
}

func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
