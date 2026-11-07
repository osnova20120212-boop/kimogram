import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

/// "Kimogram Settings": every switch the mod adds, in one place under Settings ▸ Money.
public func kimogramSettingsTitle() -> String {
    return KimogramAutoProxy.isRussian ? "Настройки Kimogram" : "Kimogram Settings"
}

private final class KimogramSettingsArguments {
    let openProxy: () -> Void
    let openAppearance: () -> Void
    let setGhostMode: (Bool) -> Void
    let set: (KimogramSettings.Key, Bool) -> Void

    init(openProxy: @escaping () -> Void, openAppearance: @escaping () -> Void, setGhostMode: @escaping (Bool) -> Void, set: @escaping (KimogramSettings.Key, Bool) -> Void) {
        self.openProxy = openProxy
        self.openAppearance = openAppearance
        self.setGhostMode = setGhostMode
        self.set = set
    }
}

private enum KimogramSettingsSection: Int32 {
    case header
    case connection
    case ghost
    case history
    case chats
    case interface
    case about
}

private enum KimogramSettingsEntry: ItemListNodeEntry {
    case header(PresentationTheme, String, String)

    case connectionHeader(PresentationTheme, String)
    case proxy(PresentationTheme, String, String)
    case connectionOption(Int32, PresentationTheme, KimogramSettings.Key, String, Bool)
    case connectionInfo(PresentationTheme, String)

    case ghostHeader(PresentationTheme, String)
    case ghostMaster(PresentationTheme, String, Bool)
    case ghostOption(Int32, PresentationTheme, KimogramSettings.Key, String, Bool)
    case ghostInfo(PresentationTheme, String)

    case historyHeader(PresentationTheme, String)
    case historyOption(Int32, PresentationTheme, KimogramSettings.Key, String, Bool)
    case historyInfo(PresentationTheme, String)

    case chatsHeader(PresentationTheme, String)
    case chatsOption(Int32, PresentationTheme, KimogramSettings.Key, String, Bool)
    case chatsInfo(PresentationTheme, String)

    case interfaceHeader(PresentationTheme, String)
    case appearance(PresentationTheme, String)
    case interfaceInfo(PresentationTheme, String)

    case about(PresentationTheme, String)

    var section: ItemListSectionId {
        switch self {
        case .header:
            return KimogramSettingsSection.header.rawValue
        case .connectionHeader, .proxy, .connectionOption, .connectionInfo:
            return KimogramSettingsSection.connection.rawValue
        case .ghostHeader, .ghostMaster, .ghostOption, .ghostInfo:
            return KimogramSettingsSection.ghost.rawValue
        case .historyHeader, .historyOption, .historyInfo:
            return KimogramSettingsSection.history.rawValue
        case .chatsHeader, .chatsOption, .chatsInfo:
            return KimogramSettingsSection.chats.rawValue
        case .interfaceHeader, .appearance, .interfaceInfo:
            return KimogramSettingsSection.interface.rawValue
        case .about:
            return KimogramSettingsSection.about.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .header:
            return 0
        case .connectionHeader:
            return 100
        case .proxy:
            return 101
        case let .connectionOption(index, _, _, _, _):
            return 110 + index
        case .connectionInfo:
            return 190
        case .ghostHeader:
            return 200
        case .ghostMaster:
            return 201
        case let .ghostOption(index, _, _, _, _):
            return 210 + index
        case .ghostInfo:
            return 240
        case .historyHeader:
            return 250
        case let .historyOption(index, _, _, _, _):
            return 260 + index
        case .historyInfo:
            return 280
        case .chatsHeader:
            return 300
        case let .chatsOption(index, _, _, _, _):
            return 310 + index
        case .chatsInfo:
            return 390
        case .interfaceHeader:
            return 400
        case .appearance:
            return 401
        case .interfaceInfo:
            return 402
        case .about:
            return 500
        }
    }

    static func ==(lhs: KimogramSettingsEntry, rhs: KimogramSettingsEntry) -> Bool {
        switch lhs {
        case let .header(lhsTheme, lhsTitle, lhsText):
            if case let .header(rhsTheme, rhsTitle, rhsText) = rhs, lhsTheme === rhsTheme, lhsTitle == rhsTitle, lhsText == rhsText {
                return true
            }
            return false
        case let .connectionHeader(lhsTheme, lhsText), let .connectionInfo(lhsTheme, lhsText), let .ghostHeader(lhsTheme, lhsText), let .ghostInfo(lhsTheme, lhsText), let .chatsHeader(lhsTheme, lhsText), let .chatsInfo(lhsTheme, lhsText), let .historyHeader(lhsTheme, lhsText), let .historyInfo(lhsTheme, lhsText), let .interfaceHeader(lhsTheme, lhsText), let .appearance(lhsTheme, lhsText), let .interfaceInfo(lhsTheme, lhsText), let .about(lhsTheme, lhsText):
            guard lhs.stableId == rhs.stableId else {
                return false
            }
            switch rhs {
            case let .connectionHeader(rhsTheme, rhsText), let .connectionInfo(rhsTheme, rhsText), let .ghostHeader(rhsTheme, rhsText), let .ghostInfo(rhsTheme, rhsText), let .chatsHeader(rhsTheme, rhsText), let .chatsInfo(rhsTheme, rhsText), let .historyHeader(rhsTheme, rhsText), let .historyInfo(rhsTheme, rhsText), let .interfaceHeader(rhsTheme, rhsText), let .appearance(rhsTheme, rhsText), let .interfaceInfo(rhsTheme, rhsText), let .about(rhsTheme, rhsText):
                return lhsTheme === rhsTheme && lhsText == rhsText
            default:
                return false
            }
        case let .proxy(lhsTheme, lhsText, lhsValue):
            if case let .proxy(rhsTheme, rhsText, rhsValue) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                return true
            }
            return false
        case let .ghostMaster(lhsTheme, lhsText, lhsValue):
            if case let .ghostMaster(rhsTheme, rhsText, rhsValue) = rhs, lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                return true
            }
            return false
        case let .ghostOption(lhsIndex, lhsTheme, lhsKey, lhsText, lhsValue):
            if case let .ghostOption(rhsIndex, rhsTheme, rhsKey, rhsText, rhsValue) = rhs, lhsIndex == rhsIndex, lhsTheme === rhsTheme, lhsKey == rhsKey, lhsText == rhsText, lhsValue == rhsValue {
                return true
            }
            return false
        case let .connectionOption(lhsIndex, lhsTheme, lhsKey, lhsText, lhsValue):
            if case let .connectionOption(rhsIndex, rhsTheme, rhsKey, rhsText, rhsValue) = rhs, lhsIndex == rhsIndex, lhsTheme === rhsTheme, lhsKey == rhsKey, lhsText == rhsText, lhsValue == rhsValue {
                return true
            }
            return false
        case let .historyOption(lhsIndex, lhsTheme, lhsKey, lhsText, lhsValue):
            if case let .historyOption(rhsIndex, rhsTheme, rhsKey, rhsText, rhsValue) = rhs, lhsIndex == rhsIndex, lhsTheme === rhsTheme, lhsKey == rhsKey, lhsText == rhsText, lhsValue == rhsValue {
                return true
            }
            return false
        case let .chatsOption(lhsIndex, lhsTheme, lhsKey, lhsText, lhsValue):
            if case let .chatsOption(rhsIndex, rhsTheme, rhsKey, rhsText, rhsValue) = rhs, lhsIndex == rhsIndex, lhsTheme === rhsTheme, lhsKey == rhsKey, lhsText == rhsText, lhsValue == rhsValue {
                return true
            }
            return false
        }
    }

    static func <(lhs: KimogramSettingsEntry, rhs: KimogramSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! KimogramSettingsArguments
        switch self {
        case let .header(theme, title, text):
            return KimogramHeaderItem(theme: theme, title: title, subtitle: text, sectionId: self.section)
        case let .connectionHeader(_, text), let .ghostHeader(_, text), let .historyHeader(_, text), let .chatsHeader(_, text), let .interfaceHeader(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .proxy(_, text, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.proxy, title: text, label: value, sectionId: self.section, style: .blocks, action: {
                arguments.openProxy()
            })
        case let .connectionInfo(_, text), let .ghostInfo(_, text), let .historyInfo(_, text), let .chatsInfo(_, text), let .interfaceInfo(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .ghostMaster(_, text, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.security, title: text, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setGhostMode(value)
            })
        case let .ghostOption(_, _, key, text, value), let .historyOption(_, _, key, text, value), let .chatsOption(_, _, key, text, value), let .connectionOption(_, _, key, text, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: text, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.set(key, value)
            })
        case let .appearance(_, text):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.appearance, title: text, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openAppearance()
            })
        case let .about(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func kimogramSettingsEntries(theme: PresentationTheme, autoProxyEnabled: Bool) -> [KimogramSettingsEntry] {
    let ru = KimogramAutoProxy.isRussian
    var entries: [KimogramSettingsEntry] = []

    entries.append(.header(theme, "Kimogram", ru ? "Привычный мессенджер, только мощнее и красивее" : "The messenger you know, more powerful and beautiful"))

    entries.append(.connectionHeader(theme, ru ? "ПОДКЛЮЧЕНИЕ" : "CONNECTION"))
    entries.append(.proxy(theme, ru ? "Прокси" : "Proxy", autoProxyEnabled ? (ru ? "Авто" : "Auto") : (ru ? "Свой" : "Manual")))
    entries.append(.connectionOption(0, theme, .fastDownloads, ru ? "Быстрая загрузка файлов" : "Faster Downloads", KimogramSettings.get(.fastDownloads)))
    entries.append(.connectionInfo(theme, ru ? "Авто-прокси сам находит рабочий бесплатный прокси, если подключиться не получается. Быстрая загрузка качает большие файлы в два раза большим числом потоков." : "Auto Proxy finds a working free proxy for you whenever the app cannot connect. Faster Downloads fetches large files with twice as many parallel parts."))

    entries.append(.ghostHeader(theme, ru ? "РЕЖИМ ПРИЗРАКА" : "GHOST MODE"))
    entries.append(.ghostMaster(theme, ru ? "Режим призрака" : "Ghost Mode", KimogramSettings.ghostModeEnabled))
    entries.append(.ghostOption(0, theme, .ghostReadReceipts, ru ? "Не отправлять «прочитано»" : "Don't Send Read Receipts", KimogramSettings.get(.ghostReadReceipts)))
    entries.append(.ghostOption(1, theme, .ghostOnline, ru ? "Не показывать «в сети»" : "Hide Online Status", KimogramSettings.get(.ghostOnline)))
    entries.append(.ghostOption(2, theme, .ghostTyping, ru ? "Не показывать «печатает»" : "Hide Typing", KimogramSettings.get(.ghostTyping)))
    entries.append(.ghostOption(3, theme, .ghostStories, ru ? "Смотреть истории тайно" : "View Stories Secretly", KimogramSettings.get(.ghostStories)))
    entries.append(.ghostInfo(theme, ru ? "Собеседники не увидят, что вы прочитали сообщение, были в сети, печатали или смотрели их историю. Когда вы сами отправляете сообщение, сервер всё равно ненадолго показывает вас в сети." : "Others won't see that you read their messages, were online, were typing or viewed their stories. Sending a message still briefly shows you online."))

    entries.append(.historyHeader(theme, ru ? "СОХРАНЕНИЕ" : "KEEP HISTORY"))
    entries.append(.historyOption(0, theme, .saveDeletedMessages, ru ? "Сохранять удалённые сообщения" : "Keep Deleted Messages", KimogramSettings.get(.saveDeletedMessages)))
    entries.append(.historyOption(1, theme, .saveEditHistory, ru ? "Сохранять историю правок" : "Keep Edit History", KimogramSettings.get(.saveEditHistory)))
    entries.append(.historyInfo(theme, ru ? "Если собеседник удалит сообщение, у вас оно останется с пометкой «🗑 Удалено». Если исправит, ниже будет видно, что было написано раньше. Работает для сообщений, которые пришли, пока настройка включена." : "Messages others delete stay with a \"🗑 Deleted\" mark, and edited messages show what they said before. Works for messages received while this is on."))

    entries.append(.chatsHeader(theme, ru ? "ЧАТЫ" : "CHATS"))
    entries.append(.chatsOption(0, theme, .hideSponsored, ru ? "Без рекламы в каналах" : "No Sponsored Messages", KimogramSettings.get(.hideSponsored)))
    entries.append(.chatsOption(1, theme, .showPeerId, ru ? "Показывать ID в профиле" : "Show ID in Profiles", KimogramSettings.get(.showPeerId)))
    entries.append(.chatsOption(2, theme, .timestampSeconds, ru ? "Время с секундами" : "Show Seconds in Time", KimogramSettings.get(.timestampSeconds)))
    entries.append(.chatsOption(3, theme, .hideStoriesBar, ru ? "Скрыть истории над чатами" : "Hide Stories Row", KimogramSettings.get(.hideStoriesBar)))
    entries.append(.chatsOption(4, theme, .hidePhoneNumber, ru ? "Скрыть мой номер в настройках" : "Hide My Number in Settings", KimogramSettings.get(.hidePhoneNumber)))
    entries.append(.chatsOption(6, theme, .confirmCalls, ru ? "Спрашивать перед звонком" : "Confirm Before Calling", KimogramSettings.get(.confirmCalls)))
    entries.append(.chatsOption(5, theme, .hidePremiumRows, ru ? "Скрыть Premium и подарки" : "Hide Premium and Gifts", KimogramSettings.get(.hidePremiumRows)))
    entries.append(.chatsInfo(theme, ru ? "ID копируется нажатием в профиле. Скрытый номер удобен для скриншотов." : "Tap an ID in a profile to copy it. A hidden number keeps it off screenshots."))

    entries.append(.interfaceHeader(theme, ru ? "ОФОРМЛЕНИЕ" : "APPEARANCE"))
    entries.append(.appearance(theme, ru ? "Тема и иконка приложения" : "Theme and App Icon"))
    entries.append(.interfaceInfo(theme, ru ? "Фиолетовая тема Kimogram стоит первой в списке цветов, там же 11 вариантов иконки." : "The violet Kimogram colours come first in the colour list, next to 11 Kimogram icons."))

    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    entries.append(.about(theme, ru ? "Kimogram \(version) (\(build)). Основан на открытом коде Telegram для iOS." : "Kimogram \(version) (\(build)). Built on the open-source Telegram for iOS."))

    return entries
}

public func kimogramSettingsController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = KimogramSettingsArguments(openProxy: {
        pushControllerImpl?(proxySettingsController(context: context))
    }, openAppearance: {
        pushControllerImpl?(themeSettingsController(context: context))
    }, setGhostMode: { value in
        KimogramSettings.setGhostMode(value)
    }, set: { key, value in
        KimogramSettings.set(key, value)
    })

    let signal = combineLatest(queue: Queue.mainQueue(), context.sharedContext.presentationData, KimogramSettings.changes(), KimogramAutoProxy.shared.enabled)
    |> map { presentationData, _, autoProxyEnabled -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(kimogramSettingsTitle()), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: kimogramSettingsEntries(theme: presentationData.theme, autoProxyEnabled: autoProxyEnabled), style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    return controller
}
