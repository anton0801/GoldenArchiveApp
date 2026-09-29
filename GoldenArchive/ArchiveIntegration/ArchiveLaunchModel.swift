import Foundation
import SwiftUI
import Combine
import UserNotifications

@MainActor
final class ArchiveLaunchModel: ObservableObject {

    enum Phase: Equatable {
        case launching
        case noInternet
        case prePermission(URL)
        case webview(URL)
        case stub
    }

    @Published var phase: Phase = .launching

    private let store = ArchiveLaunchStore.shared
    private var pushCancellable: AnyCancellable?
    private var networkCancellable: AnyCancellable?
    private var started = false
    private var configRequestInFlight = false
    private var hasSentConfig = false
    private var lastSubmittedPushToken: String?

    func start() {
        guard !started else { return }
        started = true
        observePush()
        observeConnectivityLoss()
        ArchivePushManager.shared.onTokenAvailable = { [weak self] token in
            Task { @MainActor [weak self] in
                self?.syncPushTokenIfNeeded(token)
            }
        }
        Task { await run() }
    }

    private func observePush() {
        pushCancellable = ArchivePushRouter.shared.$pendingURL
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] url in
                self?.phase = .webview(url)
            }
    }

    private func observeConnectivityLoss() {
        networkCancellable = ArchiveNetworkMonitor.shared.$isOnline
            .receive(on: RunLoop.main)
            .sink { [weak self] online in
                guard let self, self.phase == .launching, !online else { return }
                self.phase = .noInternet
            }
    }

    private func applyPhaseIfStillLaunching(_ newPhase: Phase) {
        guard phase == .launching else { return }
        phase = newPhase
    }

    private func gatherTrackingData() async {
        ArchivePushManager.shared.configureFirebaseIfPossible()
        async let conversion: Void = ArchiveAttributionManager.shared.startAndAwaitConversion()
        async let token: String? = ArchivePushManager.shared.fetchToken(timeout: store.mode == .undecided ? 3 : 1)
        _ = await (conversion, token)
    }

    private func fetchConfig() async -> ArchiveConfigResult {
        let submittedToken = ArchivePushManager.shared.fcmToken
        configRequestInFlight = true
        let result = await ArchiveConfigService.fetch()
        configRequestInFlight = false
        hasSentConfig = true
        lastSubmittedPushToken = submittedToken
        if let currentToken = ArchivePushManager.shared.fcmToken {
            syncPushTokenIfNeeded(currentToken)
        }
        return result
    }

    private func syncPushTokenIfNeeded(_ token: String) {
        guard hasSentConfig, !configRequestInFlight, token != lastSubmittedPushToken else { return }
        lastSubmittedPushToken = token
        Task { _ = await ArchiveConfigService.fetch() }
    }

    private func run() async {
        if let pushURL = ArchivePushRouter.shared.pendingURL {
            phase = .webview(pushURL)
            return
        }

        switch store.mode {
        case .stub:
            phase = .stub
        case .webview:
            await runWebViewMode()
        case .undecided:
            await runFirstLaunch()
        }
    }

    private func runFirstLaunch() async {
        guard await ArchiveNetworkMonitor.shared.currentStatus() else {
            applyPhaseIfStillLaunching(.noInternet)
            return
        }

        await gatherTrackingData()

        let result = await fetchConfig()

        switch result {
        case .webview(let url, let expires):
            let decorated = url.appendingQueryItems(ArchiveAttributionManager.shared.deepLinkQueryItems)
            store.mode = .webview
            store.savedURL = decorated
            store.expires = expires
            await proceedToWebView(decorated)
        case .stub:
            store.mode = .stub
            applyPhaseIfStillLaunching(.stub)
        case .networkError:
            applyPhaseIfStillLaunching(.noInternet)
        }
    }

    private func runWebViewMode() async {
        guard await ArchiveNetworkMonitor.shared.currentStatus() else {
            applyPhaseIfStillLaunching(.noInternet)
            return
        }

        if let savedURL = store.savedURL {
            await proceedToWebView(savedURL)
        }

        await gatherTrackingData()

        let result = await fetchConfig()

        switch result {
        case .webview(let url, let expires):
            let decorated = url.appendingQueryItems(ArchiveAttributionManager.shared.deepLinkQueryItems)
            store.savedURL = decorated
            store.expires = expires
            switch phase {
            case .webview:
                phase = .webview(decorated)
            case .prePermission:
                phase = .prePermission(decorated)
            case .launching:
                await proceedToWebView(decorated)
            default:
                break
            }
        case .networkError:
            if store.savedURL == nil {
                if await ArchiveNetworkMonitor.shared.currentStatus() {
                    await fallBackToSavedURLOrStub()
                } else {
                    applyPhaseIfStillLaunching(.noInternet)
                }
            }
        case .stub:
            if store.savedURL == nil {
                await fallBackToSavedURLOrStub()
            }
        }
    }

    private func fallBackToSavedURLOrStub() async {
        if let saved = store.savedURL {
            await proceedToWebView(saved)
        } else {
            store.mode = .stub
            applyPhaseIfStillLaunching(.stub)
        }
    }

    private func proceedToWebView(_ url: URL) async {
        if await shouldShowPrePermission() {
            applyPhaseIfStillLaunching(.prePermission(url))
        } else {
            applyPhaseIfStillLaunching(.webview(url))
        }
    }

    private func shouldShowPrePermission() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return false }

        switch store.pushSkipCount {
        case 0:
            return true
        case 1:
            guard let declined = store.pushDeclinedAt else { return true }
            return Date().timeIntervalSince(declined) > 3 * 24 * 3600
        default:
            return false
        }
    }

    func acceptPush(for url: URL) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, _ in
            Task { @MainActor in
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                self?.phase = .webview(url)
            }
        }
    }

    func skipPush(for url: URL) {
        store.pushSkipCount += 1
        store.pushDeclinedAt = Date()
        phase = .webview(url)
    }
}
