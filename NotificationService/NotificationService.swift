import UserNotifications

/// Notification Service Extension — загружает картинку из пуша (`fcm_options.image`
/// или `mutable-content` payload) и прикрепляет как вложение.
///
/// Как добавить таргет в Xcode:
///  File → New → Target… → Notification Service Extension → Product Name: NotificationService.
///  Затем замените сгенерированный NotificationService.swift на этот файл
///  (или добавьте этот файл в membership нового таргета).
import UserNotifications
import FirebaseMessaging

class NotificationService: UNNotificationServiceExtension {
    
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?
    
    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
        
        if let bestAttemptContent = bestAttemptContent {
            Messaging.serviceExtension().populateNotificationContent(bestAttemptContent, withContentHandler: contentHandler)
        }
    }
}
