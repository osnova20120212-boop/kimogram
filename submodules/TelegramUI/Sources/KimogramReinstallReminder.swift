import Foundation
import UserNotifications

/// Kimogram: a free sideload signature lasts seven days. A day before it runs out, a local
/// notification reminds to reinstall the app from the computer.
enum KimogramReinstallReminder {
    private static let identifier = "kimogram.reinstallReminder"

    static func schedule(russian: Bool) {
        let fileManager = FileManager.default
        guard let attributes = try? fileManager.attributesOfItem(atPath: Bundle.main.bundlePath), let installDate = (attributes[.creationDate] as? Date) ?? (attributes[.modificationDate] as? Date) else {
            return
        }
        let fireDate = installDate.addingTimeInterval(6.0 * 24.0 * 60.0 * 60.0)
        let interval = fireDate.timeIntervalSinceNow
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard interval > 60.0 else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Kimogram"
        content.body = russian ? "Завтра закончится подпись приложения. Переустановите Kimogram с компьютера, чтобы он продолжал открываться." : "The app's signature runs out tomorrow. Reinstall Kimogram from your computer to keep it opening."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger), withCompletionHandler: nil)
    }
}
