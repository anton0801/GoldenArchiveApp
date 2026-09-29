//
//  Records.swift
//  GoldenArchive
//
//  Domain layer — records attached to items: condition observations,
//  provenance documents, duplicate groups, wishes, goals, value notes and
//  exhibitions.
//

import Foundation

// MARK: - Condition

enum ObservationSide: String, Codable, CaseIterable, Identifiable {
    case overall
    case obverse
    case reverse
    case edge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overall: return "Whole item"
        case .obverse: return "Obverse"
        case .reverse: return "Reverse"
        case .edge: return "Edge"
        }
    }
}

enum WearLevel: String, Codable, CaseIterable, Identifiable {
    case notAssessed
    case none
    case light
    case moderate
    case heavy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notAssessed: return "Not assessed"
        case .none: return "No visible wear"
        case .light: return "Light wear"
        case .moderate: return "Moderate wear"
        case .heavy: return "Heavy wear"
        }
    }
}

enum CleaningHistory: String, Codable, CaseIterable, Identifiable {
    case unknown
    case notCleaned
    case cleanedBefore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unknown: return "Unknown"
        case .notCleaned: return "Not cleaned, as far as known"
        case .cleanedBefore: return "Cleaned before acquisition"
        }
    }
}

/// A dated observation written by the user. It is a personal note, not a
/// grade certificate; every edit keeps its date.
struct ConditionObservation: Identifiable, Codable, Hashable {
    let id: UUID
    var coinID: UUID
    var observedOn: Date
    var side: ObservationSide
    var wear: WearLevel
    var scratches: String
    var color: String
    var cleaning: CleaningHistory
    var userGrade: String
    var closeUps: [StoredFile]
    var note: String
    var revisions: [ChangeEntry]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        coinID: UUID,
        observedOn: Date,
        side: ObservationSide = .overall,
        wear: WearLevel = .notAssessed,
        scratches: String = "",
        color: String = "",
        cleaning: CleaningHistory = .unknown,
        userGrade: String = "",
        closeUps: [StoredFile] = [],
        note: String = "",
        revisions: [ChangeEntry] = [],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.coinID = coinID
        self.observedOn = observedOn
        self.side = side
        self.wear = wear
        self.scratches = scratches
        self.color = color
        self.cleaning = cleaning
        self.userGrade = userGrade
        self.closeUps = closeUps
        self.note = note
        self.revisions = revisions
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Provenance

enum DocumentType: String, Codable, CaseIterable, Identifiable {
    case receipt
    case invoice
    case certificate
    case auctionRecord
    case letter
    case oldRecord
    case photo
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .receipt: return "Receipt"
        case .invoice: return "Invoice"
        case .certificate: return "Certificate"
        case .auctionRecord: return "Auction record"
        case .letter: return "Letter"
        case .oldRecord: return "Old record"
        case .photo: return "Photo"
        case .other: return "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .receipt: return "doc.plaintext"
        case .invoice: return "doc.text"
        case .certificate: return "rosette"
        case .auctionRecord: return "hammer"
        case .letter: return "envelope"
        case .oldRecord: return "book.closed"
        case .photo: return "photo"
        case .other: return "doc"
        }
    }
}

/// The honest state of a document's file inside the local vault.
enum DocumentFileState: Codable, Hashable {
    case none
    case uploading
    case failed(reason: String)
    case available

    var title: String {
        switch self {
        case .none: return "No file"
        case .uploading: return "Uploading"
        case .failed: return "Failed"
        case .available: return "Available"
        }
    }
}

struct ProvenanceDocument: Identifiable, Codable, Hashable {
    let id: UUID
    var type: DocumentType
    var title: String
    var date: Date?
    var sourceNote: String
    var pricePaid: MoneyAmount?
    var file: StoredFile?
    var fileState: DocumentFileState
    var linkedCoinIDs: [UUID]
    var privateNote: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        type: DocumentType = .receipt,
        title: String = "",
        date: Date? = nil,
        sourceNote: String = "",
        pricePaid: MoneyAmount? = nil,
        file: StoredFile? = nil,
        fileState: DocumentFileState = .none,
        linkedCoinIDs: [UUID] = [],
        privateNote: String = "",
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.date = date
        self.sourceNote = sourceNote
        self.pricePaid = pricePaid
        self.file = file
        self.fileState = fileState
        self.linkedCoinIDs = linkedCoinIDs
        self.privateNote = privateNote
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var displayTitle: String { title.isBlank ? type.title : title }
}

// MARK: - Duplicates

enum KeepStatus: String, Codable, CaseIterable, Identifiable {
    case undecided
    case keep
    case extra

    var id: String { rawValue }

    var title: String {
        switch self {
        case .undecided: return "Undecided"
        case .keep: return "Keep"
        case .extra: return "Extra"
        }
    }
}

struct DuplicateMember: Codable, Hashable {
    var coinID: UUID
    var status: KeepStatus
}

/// Records the user marked as the same kind of item, for personal
/// bookkeeping only. Nothing here is offered for sale or trade.
struct DuplicateGroup: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var members: [DuplicateMember]
    var note: String
    var reviewedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    var coinIDs: [UUID] { members.map(\.coinID) }
    var extraCount: Int { members.filter { $0.status == .extra }.count }
}

// MARK: - Wish list

enum WishPriority: String, Codable, CaseIterable, Identifiable, Comparable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    private var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    static func < (lhs: WishPriority, rhs: WishPriority) -> Bool { lhs.rank < rhs.rank }
}

enum WishStatus: String, Codable, Hashable {
    case wanted
    case acquired
}

struct WishItem: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var kind: ItemKind
    var expected: ExpectedAttributes
    var priority: WishPriority
    /// A target price kept as the user's own note, never a quote.
    var targetNote: String
    var linkedSlot: SlotReference?
    var sourceLink: String
    var note: String
    var status: WishStatus
    var acquiredCoinID: UUID?
    var acquiredAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        kind: ItemKind = .coin,
        expected: ExpectedAttributes = ExpectedAttributes(),
        priority: WishPriority = .medium,
        targetNote: String = "",
        linkedSlot: SlotReference? = nil,
        sourceLink: String = "",
        note: String = "",
        status: WishStatus = .wanted,
        acquiredCoinID: UUID? = nil,
        acquiredAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.expected = expected
        self.priority = priority
        self.targetNote = targetNote
        self.linkedSlot = linkedSlot
        self.sourceLink = sourceLink
        self.note = note
        self.status = status
        self.acquiredCoinID = acquiredCoinID
        self.acquiredAt = acquiredAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Goals

enum GoalTarget: Codable, Hashable {
    /// Fill every required slot of the linked sets.
    case completeSets([UUID])
    /// Reach a number of physical items, optionally inside one collection.
    case itemCount(collectionID: UUID?, target: Int)
}

struct CollectionGoal: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var target: GoalTarget
    var targetDate: Date?
    var note: String
    var createdAt: Date
    var updatedAt: Date
}

// MARK: - Value notes

enum ValueNoteKind: String, Codable, CaseIterable, Identifiable {
    case personalEstimate
    case externalReference

    var id: String { rawValue }

    var title: String {
        switch self {
        case .personalEstimate: return "My own note"
        case .externalReference: return "External reference"
        }
    }
}

/// A reference amount with its date and source. It is a note, not an
/// appraisal, and never implies a sale price.
struct ValueNote: Identifiable, Codable, Hashable {
    let id: UUID
    var coinID: UUID
    var kind: ValueNoteKind
    var amount: MoneyAmount
    var sourceName: String
    var sourceURL: String
    var valueDate: Date
    var note: String
    var createdAt: Date
}

// MARK: - Exhibition

struct ExhibitItem: Identifiable, Codable, Hashable {
    let id: UUID
    var coinID: UUID
    var caption: String
}

/// A local presentation of chosen items. It is never published by the app.
struct Exhibition: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var intro: String
    var items: [ExhibitItem]
    var createdAt: Date
    var updatedAt: Date
}
