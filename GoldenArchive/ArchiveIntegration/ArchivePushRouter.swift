import Foundation
import Combine

final class ArchivePushRouter: ObservableObject {
    static let shared = ArchivePushRouter()
    private init() {}

    @Published var pendingURL: URL?

    func handle(userInfo: [AnyHashable: Any]) {
        guard let raw = extractURL(from: userInfo), let url = URL(string: raw) else { return }
        pendingURL = url
    }

    private func extractURL(from payload: [AnyHashable: Any]) -> String? {
        let root = payload as NSDictionary
        func nested(_ any: Any?) -> NSDictionary? { any as? NSDictionary }

        let raw = (root["url"] as? String)
            ?? (nested(root["data"])?["url"] as? String)
            ?? (nested(nested(root["aps"])?["data"])?["url"] as? String)
            ?? (nested(root["custom"])?["url"] as? String)

        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }
}
