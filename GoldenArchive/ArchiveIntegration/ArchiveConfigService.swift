import Foundation

enum ArchiveConfigResult {
    case webview(url: URL, expires: Date?)
    case stub
    case networkError
}

enum ArchiveConfigService {

    static func fetch() async -> ArchiveConfigResult {
        let body = buildBody()
        let bodyData: Data
        do {
            bodyData = try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])
        } catch {
            return .networkError
        }

        do {
            let response = try await ArchiveHeaderlessHTTP.post(
                to: ArchiveIntegrationConfig.configEndpoint,
                body: bodyData,
                timeout: 8
            )
            let data = response.body

            guard (200...299).contains(response.statusCode) else { return .stub }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .stub
            }

            let ok = json["ok"] as? Bool ?? false
            guard ok, let urlStr = json["url"] as? String, let url = URL(string: urlStr) else {
                return .stub
            }

            var expires: Date?
            if let ts = json["expires"] as? TimeInterval {
                expires = Date(timeIntervalSince1970: ts)
            } else if let ts = json["expires"] as? Int {
                expires = Date(timeIntervalSince1970: TimeInterval(ts))
            }
            return .webview(url: url, expires: expires)
        } catch {
            return .networkError
        }
    }

    private static func buildBody() -> [String: Any] {
        let af = ArchiveAttributionManager.shared
        var body = af.mergedTrackingData

        body["af_id"] = af.appsFlyerUID
        body["bundle_id"] = Bundle.main.bundleIdentifier ?? ""
        body["os"] = "iOS"
        body["store_id"] = ArchiveIntegrationConfig.storeID
        body["locale"] = localeRFC3066()

        if ArchivePushManager.shared.isFirebaseConfigured {
            if let token = ArchivePushManager.shared.fcmToken { body["push_token"] = token }
            if let pid = ArchivePushManager.shared.firebaseProjectID { body["firebase_project_id"] = pid }
        }

        return body
    }

    private static func localeRFC3066() -> String {
        let loc = Locale.current
        if let lang = loc.language.languageCode?.identifier {
            if let region = loc.region?.identifier { return "\(lang)_\(region)" }
            return lang
        }
        return loc.identifier
    }
}
