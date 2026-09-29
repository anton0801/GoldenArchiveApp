import UIKit
import FirebaseCore
import FirebaseMessaging
import UserNotifications

final class ArchiveAppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        ArchivePushManager.shared.configureFirebaseIfPossible()
        ArchiveAttributionManager.shared.configure()
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()

        if let userInfo = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            ArchivePushRouter.shared.handle(userInfo: userInfo)
        }
        return true
    }


    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        ArchivePushManager.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
    }
}

extension ArchiveAppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        ArchivePushRouter.shared.handle(userInfo: response.notification.request.content.userInfo)
        completionHandler()
    }
}
