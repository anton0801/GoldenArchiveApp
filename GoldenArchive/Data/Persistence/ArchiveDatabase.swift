//
//  ArchiveDatabase.swift
//  GoldenArchive
//
//  Data layer — the single source of truth on disk. The archive is kept in
//  memory as one value and written atomically as JSON after changes.
//  A file that cannot be read is moved aside, never overwritten.
//

import Foundation
import Combine

final class ArchiveDatabase {

    private(set) var snapshot: ArchiveSnapshot
    private(set) var loadIssue: String?

    private let fileURL: URL
    private let writeQueue = DispatchQueue(label: "app.GoldenArchive.archive-writes", qos: .utility)
    private let subject = PassthroughSubject<Void, Never>()
    private var notifyScheduled = false
    private var pendingWrite: DispatchWorkItem?

    var changes: AnyPublisher<Void, Never> { subject.eraseToAnyPublisher() }

    init(directory: URL? = nil) {
        let base = directory ?? ArchiveDatabase.defaultDirectory()
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("archive.json")

        if let data = try? Data(contentsOf: fileURL) {
            do {
                snapshot = try ArchiveDatabase.decoder.decode(ArchiveSnapshot.self, from: data)
            } catch {
                let backupURL = base.appendingPathComponent("archive-unreadable-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.moveItem(at: fileURL, to: backupURL)
                snapshot = ArchiveSnapshot()
                loadIssue = "The saved archive could not be read. It was kept as \(backupURL.lastPathComponent) and a new archive was started."
            }
        } else {
            snapshot = ArchiveSnapshot()
        }
    }

    static func defaultDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("GoldenArchive", isDirectory: true)
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: Reading & writing

    func read<T>(_ body: (ArchiveSnapshot) -> T) -> T {
        dispatchPrecondition(condition: .onQueue(.main))
        return body(snapshot)
    }

    func mutate(_ body: (inout ArchiveSnapshot) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        body(&snapshot)
        scheduleWrite()
        scheduleNotify()
    }

    /// Replaces the whole archive and writes it synchronously, so callers
    /// know it succeeded before they clean anything up.
    func replace(with newSnapshot: ArchiveSnapshot) throws {
        dispatchPrecondition(condition: .onQueue(.main))
        let data = try ArchiveDatabase.encoder.encode(newSnapshot)
        pendingWrite?.cancel()
        try writeQueue.sync {
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        snapshot = newSnapshot
        loadIssue = nil
        scheduleNotify()
    }

    /// Writes any pending change immediately (used when the app goes to background).
    func flush() {
        guard let pending = pendingWrite else { return }
        pending.cancel()
        pendingWrite = nil
        let data = try? ArchiveDatabase.encoder.encode(snapshot)
        writeQueue.sync { [fileURL] in
            if let data { try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        }
    }

    private func scheduleWrite() {
        pendingWrite?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingWrite = nil
            guard let data = try? ArchiveDatabase.encoder.encode(self.snapshot) else { return }
            self.writeQueue.async { [fileURL = self.fileURL] in
                try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
        }
        pendingWrite = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    private func scheduleNotify() {
        guard !notifyScheduled else { return }
        notifyScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.notifyScheduled = false
            self?.subject.send(())
        }
    }
}

extension Array where Element: Identifiable {
    mutating func upsert(_ element: Element) {
        if let index = firstIndex(where: { $0.id == element.id }) {
            self[index] = element
        } else {
            append(element)
        }
    }

    mutating func upsert(_ elements: [Element]) {
        for element in elements { upsert(element) }
    }
}
