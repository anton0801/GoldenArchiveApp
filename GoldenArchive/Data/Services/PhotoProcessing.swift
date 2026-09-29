//
//  PhotoProcessing.swift
//  GoldenArchive
//
//  Data layer — measures photos and renders user crops. Nothing here
//  changes colour, contrast or sharpness: the crop is a plain geometric
//  cut of the original pixels, stored as a separate file.
//

import UIKit
import ImageIO

enum PhotoQualityAnalyzer {

    /// Measures glare, brightness and edge energy on a downsampled copy.
    static func analyze(data: Data) -> PhotoQualityReport? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        var width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        var height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        if let orientation = properties?[kCGImagePropertyOrientation] as? UInt32, orientation >= 5 {
            swap(&width, &height)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 256
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return analyze(cgImage: thumb, pixelWidth: width, pixelHeight: height)
    }

    static func analyze(cgImage: CGImage, pixelWidth: Int, pixelHeight: Int) -> PhotoQualityReport? {
        let w = cgImage.width, h = cgImage.height
        guard w > 8, h > 8 else { return nil }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let context = CGContext(
            data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        var luma = [Double](repeating: 0, count: w * h)
        var total = 0.0
        for i in 0..<(w * h) {
            let r = Double(pixels[i * 4]), g = Double(pixels[i * 4 + 1]), b = Double(pixels[i * 4 + 2])
            let y = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
            luma[i] = y
            total += y
        }

        // Centre circle: where the coin sits inside the capture guide.
        let cx = Double(w) / 2, cy = Double(h) / 2
        let radius = Double(min(w, h)) * 0.42
        var inside = 0, blown = 0
        var edgeEnergy = 0.0, edgeSamples = 0
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let dx = Double(x) - cx, dy = Double(y) - cy
                guard dx * dx + dy * dy <= radius * radius else { continue }
                let i = y * w + x
                inside += 1
                if luma[i] >= 0.97 { blown += 1 }
                let laplacian = 4 * luma[i] - luma[i - 1] - luma[i + 1] - luma[i - w] - luma[i + w]
                edgeEnergy += abs(laplacian)
                edgeSamples += 1
            }
        }
        guard inside > 0, edgeSamples > 0 else { return nil }
        return PhotoQualityReport(
            pixelWidth: pixelWidth > 0 ? pixelWidth : w,
            pixelHeight: pixelHeight > 0 ? pixelHeight : h,
            glareFraction: Double(blown) / Double(inside),
            brightness: total / Double(w * h),
            sharpness: edgeEnergy / Double(edgeSamples)
        )
    }
}

enum PhotoCropRenderer {

    /// Rotates by quarter turns, then cuts the normalised region. Returns JPEG data.
    static func render(original data: Data, quarterTurns: Int, crop: CropRegion) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let upright = normalized(image)
        let rotated = rotate(upright, quarterTurns: quarterTurns)
        guard let cg = rotated.cgImage else { return nil }
        let rect = CGRect(
            x: (crop.x * Double(cg.width)).rounded(),
            y: (crop.y * Double(cg.height)).rounded(),
            width: (crop.width * Double(cg.width)).rounded(),
            height: (crop.height * Double(cg.height)).rounded()
        ).intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard rect.width >= 8, rect.height >= 8, let cropped = cg.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped).jpegData(compressionQuality: 0.95)
    }

    static func normalized(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    static func rotate(_ image: UIImage, quarterTurns: Int) -> UIImage {
        let turns = ((quarterTurns % 4) + 4) % 4
        guard turns != 0, let cg = image.cgImage else { return image }
        let size = CGSize(width: cg.width, height: cg.height)
        let newSize = turns % 2 == 0 ? size : CGSize(width: size.height, height: size.width)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: newSize, format: format).image { context in
            let ctx = context.cgContext
            ctx.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            ctx.rotate(by: CGFloat(turns) * .pi / 2)
            UIImage(cgImage: cg).draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        }
    }
}

final class DevicePhotoProcessor: PhotoProcessing {
    func analyze(_ data: Data) -> PhotoQualityReport? { PhotoQualityAnalyzer.analyze(data: data) }
    func crop(_ data: Data, quarterTurns: Int, region: CropRegion) -> Data? {
        PhotoCropRenderer.render(original: data, quarterTurns: quarterTurns, crop: region)
    }
}
