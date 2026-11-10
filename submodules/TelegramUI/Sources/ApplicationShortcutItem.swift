import Foundation
import UIKit
import TelegramPresentationData
import DeviceAccess
import TelegramCore

enum ApplicationShortcutItemType: String {
    case search
    case compose
    case camera
    case savedMessages
    case account
    case appIcon
    case ghost
}

struct ApplicationShortcutItem: Equatable {
    let type: ApplicationShortcutItemType
    let title: String
    let subtitle: String?
}

@available(iOS 9.1, *)
extension ApplicationShortcutItem {
    func shortcutItem() -> UIApplicationShortcutItem {
        let icon: UIApplicationShortcutIcon
        switch self.type {
            case .search:
                icon = UIApplicationShortcutIcon(type: .search)
            case .compose:
                icon = UIApplicationShortcutIcon(type: .compose)
            case .camera:
                icon = UIApplicationShortcutIcon(templateImageName: "Shortcuts/Camera")
            case .savedMessages:
                icon = UIApplicationShortcutIcon(templateImageName: "Shortcuts/SavedMessages")
            case .account:
                icon = UIApplicationShortcutIcon(templateImageName: "Shortcuts/Account")
            case .appIcon:
                icon = UIApplicationShortcutIcon(templateImageName: "Shortcuts/AppIcon")
            case .ghost:
                icon = UIApplicationShortcutIcon(systemImageName: "eye.slash")
        }
        return UIApplicationShortcutItem(type: self.type.rawValue, localizedTitle: self.title, localizedSubtitle: self.subtitle, icon: icon, userInfo: nil)
    }
}

func applicationShortcutItems(strings: PresentationStrings, otherAccountName: String?) -> [ApplicationShortcutItem] {
    if let otherAccountName = otherAccountName {
        return [
            ApplicationShortcutItem(type: .search, title: strings.Common_Search, subtitle: nil),
            ApplicationShortcutItem(type: .compose, title: strings.Compose_NewMessage, subtitle: nil),
            ApplicationShortcutItem(type: .savedMessages, title: strings.Conversation_SavedMessages, subtitle: nil),
            ApplicationShortcutItem(type: .account, title: strings.Shortcut_SwitchAccount, subtitle: otherAccountName)
        ] + (KimogramSettings.storeEdition ? [] : [kimogramGhostShortcutItem(strings: strings)])
    } else {
        return [
            ApplicationShortcutItem(type: .search, title: strings.Common_Search, subtitle: nil),
            ApplicationShortcutItem(type: .compose, title: strings.Compose_NewMessage, subtitle: nil),
            ApplicationShortcutItem(type: .savedMessages, title: strings.Conversation_SavedMessages, subtitle: nil)
        ] + (KimogramSettings.storeEdition ? [] : [kimogramGhostShortcutItem(strings: strings)])
    }
}

/// Kimogram: ghost mode on and off from the app icon.
func kimogramGhostShortcutItem(strings: PresentationStrings) -> ApplicationShortcutItem {
    let ru = strings.baseLanguageCode == "ru"
    let on = KimogramSettings.ghostModeEnabled
    return ApplicationShortcutItem(type: .ghost, title: ru ? "Режим призрака" : "Ghost Mode", subtitle: on ? (ru ? "Включён · нажмите, чтобы выключить" : "On · tap to turn off") : (ru ? "Выключен · нажмите, чтобы включить" : "Off · tap to turn on"))
}
