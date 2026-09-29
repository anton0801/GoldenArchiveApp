//
//  PhotoCropView.swift
//  GoldenArchive
//
//  Presentation layer — square crop with pan, zoom and quarter-turn
//  rotation. The result is a separate file; the original stays untouched.
//

import SwiftUI
import UIKit

struct PhotoCropView: View {
    let container: AppContainer
    let photo: CoinPhoto
    var onDone: (Int, CropRegion) -> Void
    var onCancel: () -> Void

    @State private var baseImage: UIImage?
    @State private var turns: Int
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var gestureZoom: CGFloat = 1
    @GestureState private var gestureOffset: CGSize = .zero
    @State private var didRestore = false

    init(container: AppContainer, photo: CoinPhoto, onDone: @escaping (Int, CropRegion) -> Void, onCancel: @escaping () -> Void) {
        self.container = container
        self.photo = photo
        self.onDone = onDone
        self.onCancel = onCancel
        _turns = State(initialValue: photo.quarterTurns)
    }

    private var displayImage: UIImage? {
        baseImage.map { rotate($0, turns) }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button("Cancel", action: onCancel).foregroundColor(.white).frame(minHeight: 44)
                Spacer()
                Text("Crop \(photo.side.title)")
                    .font(GAFont.headline())
                    .foregroundColor(.white)
                Spacer()
                Button("Done") {
                    if let region = region(viewport: currentViewport) { onDone(turns, region) }
                }
                .font(.headline)
                .foregroundColor(GAColor.gold)
                .frame(minHeight: 44)
            }
            .padding(.horizontal)

            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                ZStack {
                    if let image = displayImage {
                        let base = max(side / image.size.width, side / image.size.height)
                        let scale = base * zoom * gestureZoom
                        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                        let combined = clamp(CGSize(width: offset.width + gestureOffset.width, height: offset.height + gestureOffset.height), display: size, viewport: side)
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: size.width, height: size.height)
                            .offset(combined)
                            .frame(width: side, height: side)
                            .clipped()
                            .contentShape(Rectangle())
                            .gesture(dragGesture(side: side, image: image).simultaneously(with: zoomGesture(side: side, image: image)))
                            .onAppear { restoreIfNeeded(side: side, image: image) }
                    } else {
                        ProgressView().tint(.white)
                    }
                    Circle()
                        .strokeBorder(GAColor.gold.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                        .frame(width: side, height: side)
                        .allowsHitTesting(false)
                    Rectangle()
                        .strokeBorder(Color.white.opacity(0.8), lineWidth: 1)
                        .frame(width: side, height: side)
                        .allowsHitTesting(false)
                }
                .frame(width: side, height: side)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                .onAppear { currentViewport = side }
            }
            .padding(.horizontal, 16)

            Text("Drag and pinch to frame the coin. Only geometry changes — colours stay exactly as photographed.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            HStack(spacing: 12) {
                Button {
                    turns = (turns + 1) % 4
                    zoom = 1
                    offset = .zero
                } label: {
                    Label("Rotate", systemImage: "rotate.right")
                }
                .buttonStyle(.ga(.secondary))
                Button {
                    turns = 0
                    zoom = 1
                    offset = .zero
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.ga(.outline))
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .padding(.top, 8)
        .background(Color.black.ignoresSafeArea())
        .task { await loadImage() }
    }

    @State private var currentViewport: CGFloat = 300

    private func loadImage() async {
        let url = container.media.url(for: photo.original)
        let image = await Task.detached(priority: .userInitiated) {
            ThumbnailCache.downsample(url: url, maxPixel: 2000)
        }.value
        baseImage = image
    }

    private func restoreIfNeeded(side: CGFloat, image: UIImage) {
        guard !didRestore else { return }
        didRestore = true
        guard let crop = photo.crop, crop.width > 0, crop.height > 0 else { return }
        let base = max(side / image.size.width, side / image.size.height)
        let restoredZoom = min(8, max(1, side / (CGFloat(crop.width) * image.size.width * base)))
        let displayW = image.size.width * base * restoredZoom
        let displayH = image.size.height * base * restoredZoom
        zoom = restoredZoom
        offset = CGSize(
            width: (displayW - side) / 2 - CGFloat(crop.x) * displayW,
            height: (displayH - side) / 2 - CGFloat(crop.y) * displayH
        )
    }

    private func dragGesture(side: CGFloat, image: UIImage) -> some Gesture {
        DragGesture()
            .updating($gestureOffset) { value, state, _ in state = value.translation }
            .onEnded { value in
                let base = max(side / image.size.width, side / image.size.height)
                let size = CGSize(width: image.size.width * base * zoom, height: image.size.height * base * zoom)
                offset = clamp(CGSize(width: offset.width + value.translation.width, height: offset.height + value.translation.height), display: size, viewport: side)
            }
    }

    private func zoomGesture(side: CGFloat, image: UIImage) -> some Gesture {
        MagnificationGesture()
            .updating($gestureZoom) { value, state, _ in state = value }
            .onEnded { value in
                zoom = min(8, max(1, zoom * value))
                let base = max(side / image.size.width, side / image.size.height)
                let size = CGSize(width: image.size.width * base * zoom, height: image.size.height * base * zoom)
                offset = clamp(offset, display: size, viewport: side)
            }
    }

    private func clamp(_ proposed: CGSize, display: CGSize, viewport: CGFloat) -> CGSize {
        let maxX = max(0, (display.width - viewport) / 2)
        let maxY = max(0, (display.height - viewport) / 2)
        return CGSize(width: min(maxX, max(-maxX, proposed.width)), height: min(maxY, max(-maxY, proposed.height)))
    }

    /// Normalised crop in the rotated original's coordinate space.
    private func region(viewport side: CGFloat) -> CropRegion? {
        guard let image = displayImage else { return nil }
        let base = max(side / image.size.width, side / image.size.height)
        let displayW = image.size.width * base * zoom
        let displayH = image.size.height * base * zoom
        let clamped = clamp(offset, display: CGSize(width: displayW, height: displayH), viewport: side)
        let x = ((displayW - side) / 2 - clamped.width) / displayW
        let y = ((displayH - side) / 2 - clamped.height) / displayH
        return CropRegion(
            x: Double(max(0, x)),
            y: Double(max(0, y)),
            width: Double(min(1, side / displayW)),
            height: Double(min(1, side / displayH))
        )
    }

    private func rotate(_ image: UIImage, _ quarterTurns: Int) -> UIImage {
        let turns = ((quarterTurns % 4) + 4) % 4
        guard turns != 0, let cg = image.cgImage else { return image }
        let size = CGSize(width: cg.width, height: cg.height)
        let newSize = turns % 2 == 0 ? size : CGSize(width: size.height, height: size.width)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { context in
            context.cgContext.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            context.cgContext.rotate(by: CGFloat(turns) * .pi / 2)
            UIImage(cgImage: cg).draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        }
    }
}

/// Full-screen viewer that can switch between the crop and the original.
struct PhotoViewer: View {
    let photo: CoinPhoto
    var onClose: () -> Void
    @State private var showOriginal = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            StoredImageView(file: showOriginal ? photo.original : photo.displayFile, maxPixel: 1400, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(showOriginal)
            VStack(spacing: 10) {
                HStack {
                    Text(photo.side.title)
                        .font(GAFont.headline())
                        .foregroundColor(.white)
                    Spacer()
                    Button("Close", action: onClose)
                        .font(.headline)
                        .foregroundColor(GAColor.gold)
                        .frame(minHeight: 44)
                }
                if photo.cropped != nil {
                    Picker("Version", selection: $showOriginal) {
                        Text("Crop").tag(false)
                        Text("Original").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Captured \(GAFormat.dateTime(photo.capturedAt))")
                    if let report = photo.quality { Text(report.summary) }
                }
                .font(.footnote)
                .foregroundColor(.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .statusBar(hidden: true)
    }
}
