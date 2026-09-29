//
//  FileVault.swift
//  GoldenArchive
//
//  Data layer — stores the user's photos, crops, scans and documents as
//  plain files. Bytes are written exactly as received: no filters, no
//  re-encoding.
//

import Foundation
import UniformTypeIdentifiers

enum FileVaultError: LocalizedError {
    case unreadableSource
    case writeFailed
    case tooLarge(Int)

    var errorDescription: String? {
        switch self {
        case .unreadableSource: return "The file could not be read. It may be in a cloud folder that is not downloaded."
        case .writeFailed: return "The file could not be saved on this device. Check free storage."
        case .tooLarge(let mb): return "The file is larger than \(mb) MB."
        }
    }
}

final class FileVault: MediaRepository {

    static let maxImportBytes = 60 * 1024 * 1024

    let directory: URL
    private let fileManager = FileManager.default

    init(directory: URL? = nil) {
        self.directory = directory ?? ArchiveDatabase.defaultDirectory().appendingPathComponent("Files", isDirectory: true)
        try? fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    private func newFileName(contentType: String, originalName: String?) -> String {
        var ext = UTType(mimeType: contentType)?.preferredFilenameExtension
        if ext == nil, let originalName { ext = (originalName as NSString).pathExtension.lowercased() }
        let suffix = (ext?.isEmpty == false) ? ".\(ext!)" : ""
        return UUID().uuidString.lowercased() + suffix
    }

    func store(data: Data, contentType: String, originalName: String?) throws -> StoredFile {
        let name = newFileName(contentType: contentType, originalName: originalName)
        let url = directory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            throw FileVaultError.writeFailed
        }
        return StoredFile(fileName: name, contentType: contentType, byteCount: data.count, originalName: originalName)
    }

    func importFile(from url: URL, contentType: String, originalName: String?) async throws -> StoredFile {
        let name = newFileName(contentType: contentType, originalName: originalName ?? url.lastPathComponent)
        let destination = directory.appendingPathComponent(name)
        return try await Task.detached(priority: .userInitiated) { () throws -> StoredFile in
            let manager = FileManager.default
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let sourceAttributes = try? manager.attributesOfItem(atPath: url.path)
            if let size = sourceAttributes?[.size] as? Int, size > FileVault.maxImportBytes { throw FileVaultError.tooLarge(FileVault.maxImportBytes / 1024 / 1024) }
            var coordinationError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { readURL in
                do {
                    try manager.copyItem(at: readURL, to: destination)
                } catch {
                    copyError = error
                }
            }
            if coordinationError != nil || copyError != nil {
                try? manager.removeItem(at: destination)
                throw FileVaultError.unreadableSource
            }
            let attributes = try? manager.attributesOfItem(atPath: destination.path)
            let bytes = (attributes?[.size] as? Int) ?? 0
            return StoredFile(fileName: name, contentType: contentType, byteCount: bytes, originalName: originalName ?? url.lastPathComponent)
        }.value
    }

    func url(for file: StoredFile) -> URL {
        directory.appendingPathComponent(file.fileName)
    }

    func data(for file: StoredFile) -> Data? {
        try? Data(contentsOf: url(for: file))
    }

    func exists(_ file: StoredFile) -> Bool {
        fileManager.fileExists(atPath: url(for: file).path)
    }

    func delete(_ file: StoredFile) {
        guard !file.fileName.contains("/") else { return }
        try? fileManager.removeItem(at: url(for: file))
    }

    func delete(_ files: [StoredFile]) {
        files.forEach(delete)
    }

    func allStoredFileNames() -> Set<String> {
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(names.filter { !$0.hasPrefix(".") })
    }

    func deleteFiles(named names: Set<String>) {
        for name in names where !name.contains("/") {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    func deleteAllFiles() {
        deleteFiles(named: allStoredFileNames())
    }
}
