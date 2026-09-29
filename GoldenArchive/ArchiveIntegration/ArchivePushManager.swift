import Foundation
import FirebaseCore
import FirebaseMessaging

final class ArchivePushManager: NSObject {
    static let shared = ArchivePushManager()
    private override init() {}

    private(set) var fcmToken: String?
    var onTokenAvailable: ((String) -> Void)?
    private var tokenWaiters: [UUID: CheckedContinuation<String?, Never>] = [:]

    var isFirebaseConfigured: Bool { FirebaseApp.app() != nil }
    var firebaseProjectID: String? { FirebaseApp.app()?.options.projectID }

    func configureFirebaseIfPossible() {
        guard Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil else {
            return
        }
        if FirebaseApp.app() == nil {
            FirebaseConfiguration.shared.setLoggerLevel(.min)
            FirebaseApp.configure()
        }
        Messaging.messaging().delegate = self
    }

    @discardableResult
    func fetchToken(timeout: TimeInterval = 5) async -> String? {
        guard isFirebaseConfigured else { return nil }
        if let t = fcmToken { return t }

        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            let id = UUID()
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    cont.resume(returning: nil)
                    return
                }
                if let token = self.fcmToken {
                    cont.resume(returning: token)
                    return
                }
                self.tokenWaiters[id] = cont
                self.refreshToken()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let waiter = self?.tokenWaiters.removeValue(forKey: id) else { return }
                waiter.resume(returning: self?.fcmToken)
            }
        }
    }

    func didRegisterForRemoteNotifications(deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        refreshToken()
    }

    private func refreshToken() {
        guard isFirebaseConfigured else { return }
        Messaging.messaging().token { [weak self] token, _ in
            guard let token else { return }
            DispatchQueue.main.async { self?.acceptToken(token) }
        }
    }

    private func acceptToken(_ token: String) {
        guard fcmToken != token else { return }
        fcmToken = token
        let waiters = Array(tokenWaiters.values)
        tokenWaiters.removeAll()
        waiters.forEach { $0.resume(returning: token) }
        onTokenAvailable?(token)
    }
}

extension ArchivePushManager: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        DispatchQueue.main.async { [weak self] in self?.acceptToken(fcmToken) }
    }
}
