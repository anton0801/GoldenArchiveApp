import Foundation

enum ArchiveLaunchMode: String {
    case undecided
    case webview
    case stub
}

final class ArchiveLaunchStore {
    static let shared = ArchiveLaunchStore()
    private let d = UserDefaults.standard
    private init() {}

    private enum Key {
        static let mode = "wrapper_mode"
        static let url = "wrapper_saved_url"
        static let expires = "wrapper_expires"
        static let pushDeclinedAt = "push_last_declined_at"
        static let pushSkipCount = "push_skip_count"
    }

    var mode: ArchiveLaunchMode {
        get { ArchiveLaunchMode(rawValue: d.string(forKey: Key.mode) ?? "") ?? .undecided }
        set { d.set(newValue.rawValue, forKey: Key.mode) }
    }

    var savedURL: URL? {
        get { d.string(forKey: Key.url).flatMap { URL(string: $0) } }
        set { d.set(newValue?.absoluteString, forKey: Key.url) }
    }

    var expires: Date? {
        get {
            let t = d.double(forKey: Key.expires)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set {
            if let nv = newValue { d.set(nv.timeIntervalSince1970, forKey: Key.expires) }
            else { d.removeObject(forKey: Key.expires) }
        }
    }

    var isExpired: Bool {
        guard let e = expires else { return true }
        return Date() >= e
    }

    var pushDeclinedAt: Date? {
        get {
            let t = d.double(forKey: Key.pushDeclinedAt)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set {
            if let nv = newValue { d.set(nv.timeIntervalSince1970, forKey: Key.pushDeclinedAt) }
            else { d.removeObject(forKey: Key.pushDeclinedAt) }
        }
    }

    var pushSkipCount: Int {
        get { d.integer(forKey: Key.pushSkipCount) }
        set { d.set(newValue, forKey: Key.pushSkipCount) }
    }
}
