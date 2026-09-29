//
//  SystemBridges.swift
//  GoldenArchive
//
//  Presentation layer — UIKit pickers and sheets that SwiftUI on iOS 15
//  does not offer natively.
//

import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers
import VisionKit
import SafariServices
import AVFoundation

// MARK: - Photo library (PHPicker needs no library permission)

struct PickedImage {
    var data: Data
    var contentType: String
}

struct PhotoLibraryPicker: UIViewControllerRepresentable {
    var selectionLimit: Int = 1
    var onFinish: ([PickedImage]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = selectionLimit
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onFinish: ([PickedImage]) -> Void
        init(onFinish: @escaping ([PickedImage]) -> Void) { self.onFinish = onFinish }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else {
                onFinish([])
                return
            }
            let group = DispatchGroup()
            var images: [Int: PickedImage] = [:]
            let lock = NSLock()
            for (index, result) in results.enumerated() {
                let provider = result.itemProvider
                let type = [UTType.heic, .jpeg, .png, .image].first { provider.hasItemConformingToTypeIdentifier($0.identifier) } ?? .image
                group.enter()
                provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                    if let data {
                        let mime = type == .image ? "image/jpeg" : (type.preferredMIMEType ?? "image/jpeg")
                        lock.lock()
                        images[index] = PickedImage(data: data, contentType: mime)
                        lock.unlock()
                    }
                    group.leave()
                }
            }
            group.notify(queue: .main) { [onFinish] in
                onFinish(images.keys.sorted().compactMap { images[$0] })
            }
        }
    }
}

// MARK: - Files

struct DocumentFilePicker: UIViewControllerRepresentable {
    var types: [UTType] = [.pdf, .image, .plainText, .rtf]
    var onPick: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onPick(urls.first) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onPick(nil) }
    }
}

enum FileTypes {
    static func mimeType(for url: URL) -> String {
        UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }
}

// MARK: - Document scanner

struct DocumentScanner: UIViewControllerRepresentable {
    var onFinish: (Data?) -> Void

    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: (Data?) -> Void
        init(onFinish: @escaping (Data?) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            // Pages are combined into one PDF, exactly as scanned.
            let data = NSMutableData()
            let first = scan.imageOfPage(at: 0)
            UIGraphicsBeginPDFContextToData(data, CGRect(origin: .zero, size: first.size), nil)
            for index in 0..<scan.pageCount {
                let page = scan.imageOfPage(at: index)
                UIGraphicsBeginPDFPageWithInfo(CGRect(origin: .zero, size: page.size), nil)
                page.draw(in: CGRect(origin: .zero, size: page.size))
            }
            UIGraphicsEndPDFContext()
            onFinish(data as Data)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { onFinish(nil) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { onFinish(nil) }
    }
}

// MARK: - Share & web

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    var onComplete: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onComplete?() }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct SafariView: UIViewControllerRepresentable {
    var url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(hex: 0x172A46)
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

struct ShareItem: Identifiable {
    let id = UUID()
    var items: [Any]
}

struct WebLink: Identifiable {
    let id = UUID()
    var url: URL

    /// Only http(s) links are opened.
    init?(_ string: String) {
        guard let url = URL(string: string.trimmed), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return nil }
        self.url = url
    }

    init(url: URL) { self.url = url }
}

// MARK: - Camera permission

enum CameraPermission {
    enum State {
        case notDetermined
        case authorized
        case denied
        case unavailable
    }

    static var state: State {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return .unavailable }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    /// Shows the system prompt only when the user tapped a camera button.
    static func request(_ completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
