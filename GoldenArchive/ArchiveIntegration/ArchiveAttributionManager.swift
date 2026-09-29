import Foundation
import AppsFlyerLib
import AppTrackingTransparency

final class ArchiveAttributionManager: NSObject {
    static let shared = ArchiveAttributionManager()
    private override init() {}

    private(set) var conversionData: [String: Any]?
    private(set) var deepLinkData: [String: Any]?
    private(set) var conversionArrivedFirst = false

    private var conversionSettled = false
    private var deepLinkSettled = false
    private var conversionAttempts = 0
    private var continuation: CheckedContinuation<Void, Never>?
    private var didResume = false
    private var deepLinkGraceScheduled = false

    func configure() {
        let af = AppsFlyerLib.shared()
        af.appsFlyerDevKey = ArchiveIntegrationConfig.appsFlyerDevKey
        af.appleAppID = ArchiveIntegrationConfig.appleAppID
        af.delegate = self
        af.deepLinkDelegate = self
        af.currencyCode = "USD"
    }

    var appsFlyerUID: String { AppsFlyerLib.shared().getAppsFlyerUID() }

    var mergedTrackingData: [String: Any] {
        var merged = conversionData ?? [:]
        let deepLinkOwnFields = (deepLinkData ?? [:]).filter {
            $0.key == "deep_link_value" || $0.key.hasPrefix("deep_link_sub")
        }
        if conversionArrivedFirst {
            deepLinkOwnFields.forEach { if merged[$0.key] == nil { merged[$0.key] = $0.value } }
        } else {
            deepLinkOwnFields.forEach { merged[$0.key] = $0.value }
        }
        return merged
    }

    var deepLinkQueryItems: [URLQueryItem] {
        mergedTrackingData.compactMap { key, value in
            guard key == "deep_link_value" || key.hasPrefix("deep_link_sub") else { return nil }
            let str = "\(value)"
            guard !str.isEmpty, str.lowercased() != "null", str != "<null>" else { return nil }
            return URLQueryItem(name: key, value: str)
        }
    }

    func startAndAwaitConversion() async {
        await requestTrackingIfNeeded()
        AppsFlyerLib.shared().start(completionHandler: nil)

        if conversionSettled && deepLinkSettled { return }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.continuation = cont
            self.resume()
        }
    }

    private func resume(force: Bool = false) {
        guard !didResume else { return }
        guard force || (conversionSettled && deepLinkSettled) else {
            if conversionSettled && !deepLinkGraceScheduled {
                deepLinkGraceScheduled = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    self?.resume(force: true)
                }
            }
            return
        }
        guard let continuation else { return }
        didResume = true
        self.continuation = nil
        continuation.resume()
    }

    private func requestTrackingIfNeeded() async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        _ = await ATTrackingManager.requestTrackingAuthorization()
    }
}

extension ArchiveAttributionManager: AppsFlyerLibDelegate {
    func onConversionDataSuccess(_ conversionInfo: [AnyHashable: Any]) {
        conversionAttempts += 1
        let data = conversionInfo as? [String: Any] ?? [:]
        guard !data.isEmpty else { return }
        let isOrganic = (data["af_status"] as? String)?.caseInsensitiveCompare("organic") == .orderedSame

        conversionData = data

        if isOrganic && conversionAttempts == 1 && ArchiveLaunchStore.shared.mode == .undecided {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await self?.recheckViaInstallDataAPI()
            }
            return
        }

        finalizeConversion()
    }

    func onConversionDataFail(_ error: Error) {
    }

    private func finalizeConversion() {
        conversionSettled = true
        if !deepLinkSettled { conversionArrivedFirst = true }
        resume()
    }

    private func recheckViaInstallDataAPI() async {
        defer { finalizeConversion() }

        var comps = URLComponents(string: "https://gcdsdk.appsflyer.com/install_data/v4.0/\(ArchiveIntegrationConfig.appleAppID)")
        comps?.queryItems = [
            URLQueryItem(name: "devkey", value: ArchiveIntegrationConfig.appsFlyerDevKey),
            URLQueryItem(name: "device_id", value: appsFlyerUID),
        ]
        guard let url = comps?.url else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        conversionData = json
    }
}

extension URL {
    func appendingQueryItems(_ newItems: [URLQueryItem]) -> URL {
        guard !newItems.isEmpty,
              var comps = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        var items = comps.queryItems ?? []
        let existing = Set(items.map { $0.name })
        items.append(contentsOf: newItems.filter { !existing.contains($0.name) })
        comps.queryItems = items
        return comps.url ?? self
    }
}

extension ArchiveAttributionManager: DeepLinkDelegate {
    func didResolveDeepLink(_ result: DeepLinkResult) {
        if result.status == .found, let deepLink = result.deepLink, deepLinkData == nil {
            deepLinkData = deepLink.clickEvent as? [String: Any] ?? [:]
        }
        deepLinkSettled = true
        resume()
    }
}
