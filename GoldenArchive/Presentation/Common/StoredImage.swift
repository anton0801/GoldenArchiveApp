//
//  StoredImage.swift
//  GoldenArchive
//
//  Presentation layer — displays the user's own photos. Images are only
//  downsampled for display; no filter, tint or enhancement is applied.
//

import SwiftUI
import UIKit
import ImageIO

final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, UIImage>()

    init() { cache.countLimit = 300 }

    func image(for url: URL, maxPixel: CGFloat) -> UIImage? {
        cache.object(forKey: key(url, maxPixel))
    }

    func clear() { cache.removeAllObjects() }

    func store(_ image: UIImage, for url: URL, maxPixel: CGFloat) {
        cache.setObject(image, forKey: key(url, maxPixel))
    }

    private func key(_ url: URL, _ maxPixel: CGFloat) -> NSString {
        "\(url.lastPathComponent)#\(Int(maxPixel))" as NSString
    }

    static func downsample(url: URL, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Resolves stored files to URLs for display, set once by the app at launch.
enum MediaURLResolver {
    static var media: MediaRepository?
}

struct StoredImageView: View {
    var file: StoredFile?
    var maxPixel: CGFloat = 600
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if failed || file == nil {
                PhotoPlaceholder(missing: file != nil)
            } else {
                Rectangle().fill(GAColor.silver.opacity(0.5))
                ProgressView().tint(GAColor.navy)
            }
        }
        .task(id: file?.fileName) { await load() }
    }

    private func load() async {
        guard let file, let media = MediaURLResolver.media else {
            image = nil
            failed = file != nil
            return
        }
        let url = media.url(for: file)
        if let cached = ThumbnailCache.shared.image(for: url, maxPixel: maxPixel) {
            image = cached
            return
        }
        let pixel = maxPixel * UIScreen.main.scale
        let loaded = await Task.detached(priority: .userInitiated) {
            ThumbnailCache.downsample(url: url, maxPixel: pixel)
        }.value
        if let loaded {
            ThumbnailCache.shared.store(loaded, for: url, maxPixel: maxPixel)
            image = loaded
        } else {
            failed = true
        }
    }
}

/// Neutral placeholder for items without a photo — not decorative art.
struct PhotoPlaceholder: View {
    var missing = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [GAColor.silver.opacity(0.7), GAColor.silver.opacity(0.35)], startPoint: .top, endPoint: .bottom)
            Image(systemName: missing ? "exclamationmark.triangle" : "circle.dashed")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(GAColor.navy.opacity(0.45))
        }
        .accessibilityLabel(missing ? "Photo file missing" : "No photo")
    }
}

struct CoinThumbnail: View {
    var coin: Coin
    var size: CGFloat = 56

    var body: some View {
        StoredImageView(file: coin.primaryPhoto?.displayFile, maxPixel: size * 2)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).strokeBorder(GAColor.stroke, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// A standard list row for an item.
struct CoinRow: View {
    var coin: Coin
    var trailing: String?
    var showsChevron = true

    var body: some View {
        HStack(spacing: 12) {
            CoinThumbnail(coin: coin, size: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text(coin.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundColor(GAColor.text)
                    .lineLimit(2)
                if !coin.subtitle.isEmpty {
                    Text(coin.subtitle)
                        .font(.footnote)
                        .foregroundColor(GAColor.textSecondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    if coin.quantity > 1 { StatusPill(text: "×\(coin.quantity)", tint: GAColor.navy) }
                    if coin.needsReview { StatusPill(text: "Needs review", tint: GAColor.ember, symbol: "exclamationmark.circle") }
                    if coin.isArchived { StatusPill(text: "Archived", tint: GAColor.silver) }
                }
            }
            Spacer(minLength: 6)
            if let trailing {
                Text(trailing)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(GAColor.textSecondary)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundColor(GAColor.textTertiary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
