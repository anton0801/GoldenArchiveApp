//
//  PhotoSetEditor.swift
//  GoldenArchive
//
//  Presentation layer — Photo Capture / Crop. Guides the user through the
//  obverse, reverse and edge. Used by Add Coin and by Coin Details.
//

import SwiftUI

struct PhotoSetEditor: View {
    let container: AppContainer
    @Binding var photos: [CoinPhoto]
    @Binding var openLibraryOnAppear: Bool
    var showsInstructions = true

    @State private var cameraSide: PhotoSide?
    @State private var librarySide: PhotoSide?
    @State private var cropTarget: CoinPhoto?
    @State private var viewing: CoinPhoto?
    @State private var alert: PhotoAlert?

    private struct PhotoAlert: Identifiable {
        let id = UUID()
        var title: String
        var message: String
        var offersSettings: Bool
        var fallbackSide: PhotoSide?
    }

    private let mainSides: [PhotoSide] = [.obverse, .reverse, .edge]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsInstructions { instructions }
            ForEach(mainSides) { side in
                sideCard(side)
            }
            detailPhotos
        }
        .fullScreenCover(item: $cameraSide) { side in
            CameraCaptureView(container: container, side: side, onUse: { data, type in
                intake(data: data, type: type, side: side)
                cameraSide = nil
            }, onCancel: { cameraSide = nil })
        }
        .sheet(item: $librarySide) { side in
            PhotoLibraryPicker(selectionLimit: 1) { picked in
                librarySide = nil
                if let first = picked.first { intake(data: first.data, type: first.contentType, side: side) }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $cropTarget) { photo in
            PhotoCropView(container: container, photo: photo, onDone: { turns, region in
                applyCrop(photo, turns: turns, region: region)
                cropTarget = nil
            }, onCancel: { cropTarget = nil })
        }
        .fullScreenCover(item: $viewing) { photo in
            PhotoViewer(photo: photo) { viewing = nil }
        }
        .alert(item: $alert) { item in
            if item.offersSettings {
                return Alert(
                    title: Text(item.title),
                    message: Text(item.message),
                    primaryButton: .default(Text("Open Settings")) { CameraPermission.openSettings() },
                    secondaryButton: .cancel(Text("Choose Photo")) { librarySide = item.fallbackSide }
                )
            }
            return Alert(title: Text(item.title), message: Text(item.message), dismissButton: .default(Text("OK")))
        }
        .onAppear {
            if openLibraryOnAppear {
                openLibraryOnAppear = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { librarySide = nextSide }
            }
        }
    }

    private var nextSide: PhotoSide {
        mainSides.first { side in !photos.contains { $0.side == side } } ?? .detail
    }

    // MARK: Sections

    private var instructions: some View {
        HStack(alignment: .top, spacing: 14) {
            ArtworkView(artwork: .scanLens)
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Before you open the camera")
                    .font(.headline)
                    .foregroundColor(GAColor.text)
                VStack(alignment: .leading, spacing: 4) {
                    tip("Matte, neutral background and soft side light.")
                    tip("Hold the coin by its edge; fill the guide.")
                    tip("Photos are stored unfiltered; crops are saved separately.")
                }
            }
        }
        .gaCard()
    }

    private func tip(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "circle.fill").font(.system(size: 5)).padding(.top, 6).foregroundColor(GAColor.bronze)
            Text(text).font(.footnote).foregroundColor(GAColor.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func sideCard(_ side: PhotoSide) -> some View {
        let photo = photos.first { $0.side == side }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(side.title)
                    .font(GAFont.headline())
                    .foregroundColor(GAColor.text)
                if side == .obverse { StatusPill(text: "Recommended", tint: GAColor.gold) }
                Spacer()
                if photo != nil {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(GAColor.success)
                        .accessibilityLabel("Added")
                }
            }
            if let photo {
                HStack(alignment: .top, spacing: 12) {
                    Button { viewing = photo } label: {
                        StoredImageView(file: photo.displayFile, maxPixel: 220)
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(alignment: .bottomTrailing) {
                                if photo.cropped != nil {
                                    Image(systemName: "crop")
                                        .font(.caption2.weight(.bold))
                                        .padding(5)
                                        .background(Circle().fill(GAColor.navy))
                                        .foregroundColor(GAColor.gold)
                                        .padding(4)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View \(side.title.lowercased()) photo")
                    VStack(alignment: .leading, spacing: 6) {
                        qualityNote(photo)
                        HStack(spacing: 8) {
                            Button("Retake") { openCamera(side) }
                                .buttonStyle(.ga(.quiet, compact: true, fullWidth: false))
                            Button("Crop") { cropTarget = photo }
                                .buttonStyle(.ga(.quiet, compact: true, fullWidth: false))
                        }
                        Button(role: .destructive) { remove(photo) } label: {
                            Label("Remove Photo", systemImage: "trash")
                                .font(.footnote.weight(.semibold))
                        }
                        .foregroundColor(GAColor.danger)
                        .frame(minHeight: 32)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Button {
                        openCamera(side)
                    } label: {
                        Label(side == .obverse ? "Capture" : "Add \(side.title)", systemImage: "camera.fill")
                    }
                    .buttonStyle(.ga(side == .obverse ? .primary : .secondary, compact: true))
                    Button {
                        librarySide = side
                    } label: {
                        Label("Choose Photo", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.ga(.outline, compact: true))
                }
            }
        }
        .gaCard()
    }

    @ViewBuilder
    private func qualityNote(_ photo: CoinPhoto) -> some View {
        if let report = photo.quality {
            if report.notes.isEmpty {
                Label("\(report.pixelWidth)×\(report.pixelHeight) px · looks clear", systemImage: "checkmark.seal")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(GAColor.successText)
            } else {
                ForEach(report.notes, id: \.self) { note in
                    Label(note, systemImage: report.hasGlare && note.hasPrefix("Glare") ? "sun.max.fill" : "exclamationmark.triangle")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(GAColor.emberText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            Text("Photo quality could not be measured.")
                .font(.caption)
                .foregroundColor(GAColor.textSecondary)
        }
    }

    private var detailPhotos: some View {
        let details = photos.filter { $0.side == .detail }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Close-ups")
                    .font(GAFont.headline())
                    .foregroundColor(GAColor.text)
                Text("optional")
                    .font(.caption)
                    .foregroundColor(GAColor.textSecondary)
                Spacer()
                Menu {
                    Button { openCamera(.detail) } label: { Label("Capture", systemImage: "camera") }
                    Button { librarySide = .detail } label: { Label("Choose Photo", systemImage: "photo") }
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(GAColor.bronzeText)
                        .frame(minHeight: 44)
                }
            }
            if !details.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(details) { photo in
                            StoredImageView(file: photo.displayFile, maxPixel: 180)
                                .frame(width: 76, height: 76)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .onTapGesture { viewing = photo }
                                .contextMenu {
                                    Button { cropTarget = photo } label: { Label("Crop", systemImage: "crop") }
                                    Button(role: .destructive) { remove(photo) } label: { Label("Remove Photo", systemImage: "trash") }
                                }
                        }
                    }
                }
                Text("Touch and hold a close-up to crop or remove it.")
                    .font(.caption)
                    .foregroundColor(GAColor.textSecondary)
            }
        }
        .gaCard()
    }

    // MARK: Actions

    private func openCamera(_ side: PhotoSide) {
        switch CameraPermission.state {
        case .authorized:
            cameraSide = side
        case .notDetermined:
            CameraPermission.request { granted in
                if granted { cameraSide = side }
                else { alert = PhotoAlert(title: "Camera is off", message: "You can allow the camera in Settings, or choose a photo from your library.", offersSettings: true, fallbackSide: side) }
            }
        case .denied:
            alert = PhotoAlert(title: "Camera is off", message: "You can allow the camera in Settings, or choose a photo from your library.", offersSettings: true, fallbackSide: side)
        case .unavailable:
            alert = PhotoAlert(title: "No camera available", message: "This device has no camera. Use Choose Photo instead.", offersSettings: false, fallbackSide: nil)
        }
    }

    private func intake(data: Data, type: String, side: PhotoSide) {
        do {
            let photo = try container.photoIntake.intake(data: data, contentType: type, side: side)
            if side != .detail, let index = photos.firstIndex(where: { $0.side == side }) {
                container.photoIntake.remove(photos[index])
                photos[index] = photo
            } else {
                photos.append(photo)
            }
        } catch {
            alert = PhotoAlert(title: "Photo not saved", message: error.localizedDescription, offersSettings: false, fallbackSide: nil)
        }
    }

    private func applyCrop(_ photo: CoinPhoto, turns: Int, region: CropRegion) {
        do {
            let updated = try container.photoIntake.applyCrop(to: photo, quarterTurns: turns, region: region)
            if let index = photos.firstIndex(where: { $0.id == photo.id }) { photos[index] = updated }
        } catch {
            alert = PhotoAlert(title: "Crop not saved", message: error.localizedDescription, offersSettings: false, fallbackSide: nil)
        }
    }

    private func remove(_ photo: CoinPhoto) {
        container.photoIntake.remove(photo)
        photos.removeAll { $0.id == photo.id }
    }
}
