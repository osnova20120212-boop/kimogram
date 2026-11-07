import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

/// "Kimogram Settings": every switch the mod adds, under Settings ▸ Money.
///
/// The first page is a short menu (proxy, ghost mode, history, chats, profile, appearance); each
/// topic opens its own page. Pages are described as data (`KimogramPageSection`), and one generic
/// list controller draws any of them, so adding a switch is one line in a page below.
public func kimogramSettingsTitle() -> String {
    return KimogramAutoProxy.isRussian ? "Настройки Kimogram" : "Kimogram Settings"
}

// MARK: - Page model

enum KimogramRow {
    /// The animated logo at the top of the first page.
    case hero(title: String, subtitle: String)
    /// A switch bound to one Kimogram key, with an optional one-line explanation under it.
    case toggle(KimogramSettings.Key, title: String, text: String?)
    /// The master ghost-mode switch, on when every ghost option is on.
    case ghostMaster(title: String)
    /// A row that opens another page or screen, with its current value on the right.
    case link(title: String, icon: UIImage?, label: String, action: (KimogramPageEnvironment) -> Void)
    /// One option of a single-choice page.
    case check(title: String, checked: Bool, action: () -> Void)
}

struct KimogramPageSection {
    var header: String?
    var rows: [KimogramRow]
    var footer: String?

    init(header: String? = nil, rows: [KimogramRow], footer: String? = nil) {
        self.header = header
        self.rows = rows
        self.footer = footer
    }
}

final class KimogramPageEnvironment {
    let context: AccountContext
    var push: (ViewController) -> Void = { _ in }

    init(context: AccountContext) {
        self.context = context
    }
}

// MARK: - Generic page controller

private final class KimogramPageArguments {
    let environment: KimogramPageEnvironment
    var sections: [KimogramPageSection] = []

    init(environment: KimogramPageEnvironment) {
        self.environment = environment
    }

    func row(section: Int32, index: Int32) -> KimogramRow? {
        guard section >= 0, Int(section) < self.sections.count else {
            return nil
        }
        let rows = self.sections[Int(section)].rows
        guard index >= 0, Int(index) < rows.count else {
            return nil
        }
        return rows[Int(index)]
    }
}

private enum KimogramPageEntryKind: Equatable {
    case hero(String, String)
    case toggle(String, String?, Bool)
    case link(String, String)
    case check(String, Bool)
}

private enum KimogramPageEntry: ItemListNodeEntry {
    case header(section: Int32, text: String)
    case row(section: Int32, index: Int32, kind: KimogramPageEntryKind)
    case footer(section: Int32, text: String)

    var section: ItemListSectionId {
        switch self {
        case let .header(section, _), let .row(section, _, _), let .footer(section, _):
            return section
        }
    }

    var stableId: Int32 {
        switch self {
        case let .header(section, _):
            return section * 1000
        case let .row(section, index, _):
            return section * 1000 + 1 + index
        case let .footer(section, _):
            return section * 1000 + 999
        }
    }

    static func ==(lhs: KimogramPageEntry, rhs: KimogramPageEntry) -> Bool {
        switch lhs {
        case let .header(lhsSection, lhsText):
            if case let .header(rhsSection, rhsText) = rhs, lhsSection == rhsSection, lhsText == rhsText {
                return true
            }
            return false
        case let .row(lhsSection, lhsIndex, lhsKind):
            if case let .row(rhsSection, rhsIndex, rhsKind) = rhs, lhsSection == rhsSection, lhsIndex == rhsIndex, lhsKind == rhsKind {
                return true
            }
            return false
        case let .footer(lhsSection, lhsText):
            if case let .footer(rhsSection, rhsText) = rhs, lhsSection == rhsSection, lhsText == rhsText {
                return true
            }
            return false
        }
    }

    static func <(lhs: KimogramPageEntry, rhs: KimogramPageEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! KimogramPageArguments
        switch self {
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .footer(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .row(section, index, kind):
            let row = arguments.row(section: section, index: index)
            switch kind {
            case let .hero(title, subtitle):
                return KimogramHeaderItem(theme: presentationData.theme, title: title, subtitle: subtitle, sectionId: self.section)
            case let .toggle(title, text, value):
                return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, text: text, value: value, maximumNumberOfLines: 2, sectionId: self.section, style: .blocks, updated: { value in
                    guard let row else {
                        return
                    }
                    switch row {
                    case let .toggle(key, _, _):
                        KimogramSettings.set(key, value)
                    case .ghostMaster:
                        KimogramSettings.setGhostMode(value)
                    default:
                        break
                    }
                })
            case let .link(title, label):
                var icon: UIImage?
                if let row, case let .link(_, rowIcon, _, _) = row {
                    icon = rowIcon
                }
                return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: icon, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                    if let row, case let .link(_, _, _, action) = row {
                        action(arguments.environment)
                    }
                })
            case let .check(title, checked):
                return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                    if let row, case let .check(_, _, action) = row {
                        action()
                    }
                })
            }
        }
    }
}

private func kimogramPageEntries(sections: [KimogramPageSection]) -> [KimogramPageEntry] {
    var entries: [KimogramPageEntry] = []
    for (sectionIndex, section) in sections.enumerated() {
        let sectionId = Int32(sectionIndex)
        if let header = section.header {
            entries.append(.header(section: sectionId, text: header))
        }
        for (rowIndex, row) in section.rows.enumerated() {
            let kind: KimogramPageEntryKind
            switch row {
            case let .hero(title, subtitle):
                kind = .hero(title, subtitle)
            case let .toggle(key, title, text):
                kind = .toggle(title, text, KimogramSettings.get(key))
            case let .ghostMaster(title):
                kind = .toggle(title, nil, KimogramSettings.ghostModeEnabled)
            case let .link(title, _, label, _):
                kind = .link(title, label)
            case let .check(title, checked, _):
                kind = .check(title, checked)
            }
            entries.append(.row(section: sectionId, index: Int32(rowIndex), kind: kind))
        }
        if let footer = section.footer {
            entries.append(.footer(section: sectionId, text: footer))
        }
    }
    return entries
}

/// Draws one page. `build` runs again whenever a Kimogram switch or the auto-proxy state changes,
/// so labels such as "On"/"Off" on the first page stay current.
func kimogramPageController(context: AccountContext, title: String, build: @escaping (Bool) -> [KimogramPageSection]) -> ViewController {
    let environment = KimogramPageEnvironment(context: context)
    let arguments = KimogramPageArguments(environment: environment)

    let signal = combineLatest(queue: Queue.mainQueue(), context.sharedContext.presentationData, KimogramSettings.changes(), KimogramAutoProxy.shared.enabled)
    |> map { presentationData, _, autoProxyEnabled -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let sections = build(autoProxyEnabled)
        arguments.sections = sections
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: kimogramPageEntries(sections: sections), style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    environment.push = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    return controller
}

/// A page of mutually exclusive options; picking one applies it and goes back.
func kimogramChoiceController(context: AccountContext, title: String, footer: String?, options: [String], selected: @escaping () -> Int, select: @escaping (Int) -> Void) -> ViewController {
    var popImpl: (() -> Void)?
    let controller = kimogramPageController(context: context, title: title, build: { _ in
        let current = selected()
        let rows: [KimogramRow] = options.enumerated().map { index, option in
            return .check(title: option, checked: index == current, action: {
                select(index)
                popImpl?()
            })
        }
        return [KimogramPageSection(rows: rows, footer: footer)]
    })
    popImpl = { [weak controller] in
        let _ = (controller?.navigationController as? NavigationController)?.popViewController(animated: true)
    }
    return controller
}

// MARK: - Kimogram pages

private func countLabel(_ keys: [KimogramSettings.Key], _ ru: Bool) -> String {
    let on = keys.filter { KimogramSettings.get($0) }.count
    if on == 0 {
        return ru ? "Выкл" : "Off"
    } else if on == keys.count {
        return ru ? "Все" : "All"
    } else {
        return "\(on) / \(keys.count)"
    }
}

private let ghostKeys: [KimogramSettings.Key] = [.ghostReadReceipts, .ghostOnline, .ghostTyping, .ghostStories, .ghostVoiceListened]
private let historyKeys: [KimogramSettings.Key] = [.saveDeletedMessages, .saveEditHistory, .keepSelfDestructing, .saveProtected]

private func doubleTapTitles(_ ru: Bool) -> [String] {
    return ru ? ["Реакция", "Ответить", "Открыть меню", "Ничего"] : ["Reaction", "Reply", "Open Menu", "Nothing"]
}

private func ghostPage(context: AccountContext) -> ViewController {
    let ru = KimogramAutoProxy.isRussian
    return kimogramPageController(context: context, title: ru ? "Режим призрака" : "Ghost Mode", build: { _ in
        return [
            KimogramPageSection(rows: [
                .ghostMaster(title: ru ? "Режим призрака" : "Ghost Mode")
            ], footer: ru ? "Включает всё ниже одним касанием." : "Turns on everything below at once."),
            KimogramPageSection(header: ru ? "ЧТО СКРЫВАТЬ" : "WHAT TO HIDE", rows: [
                .toggle(.ghostReadReceipts, title: ru ? "Не отправлять «прочитано»" : "Don't Send Read Receipts", text: ru ? "Галочки у собеседника останутся серыми" : "Their ticks stay grey"),
                .toggle(.ghostOnline, title: ru ? "Не показывать «в сети»" : "Hide Online Status", text: nil),
                .toggle(.ghostTyping, title: ru ? "Не показывать «печатает»" : "Hide Typing", text: nil),
                .toggle(.ghostStories, title: ru ? "Смотреть истории тайно" : "View Stories Secretly", text: nil),
                .toggle(.ghostVoiceListened, title: ru ? "Слушать голосовые тайно" : "Listen to Voice Secretly", text: ru ? "Голосовое и кружок останутся «непрослушанными»" : "Voice and video messages stay unplayed for them")
            ]),
            KimogramPageSection(header: ru ? "ИСКЛЮЧЕНИЕ" : "EXCEPTION", rows: [
                .toggle(.ghostReadOnReply, title: ru ? "Прочитано, когда отвечаю" : "Mark Read When I Reply", text: ru ? "Ответ сам отмечает чат прочитанным" : "Replying marks the chat as read")
            ], footer: ru ? "Когда вы сами отправляете сообщение, сервер всё равно ненадолго показывает вас в сети." : "Sending a message still briefly shows you online.")
        ]
    })
}

private func historyPage(context: AccountContext) -> ViewController {
    let ru = KimogramAutoProxy.isRussian
    return kimogramPageController(context: context, title: ru ? "Сохранение" : "Keep History", build: { _ in
        return [
            KimogramPageSection(header: ru ? "СООБЩЕНИЯ" : "MESSAGES", rows: [
                .toggle(.saveDeletedMessages, title: ru ? "Сохранять удалённые" : "Keep Deleted Messages", text: ru ? "Останутся у вас с пометкой 🗑" : "They stay with a 🗑 mark"),
                .toggle(.saveEditHistory, title: ru ? "Сохранять историю правок" : "Keep Edit History", text: ru ? "Под исправленным видно, что было раньше" : "See what an edited message said before"),
                .toggle(.keepSelfDestructing, title: ru ? "Не удалять исчезающие" : "Keep Self-Destructing", text: ru ? "Сообщения с таймером и одноразовые фото останутся" : "Timed messages and view-once media stay")
            ], footer: ru ? "Работает для сообщений, которые пришли, пока настройка включена." : "Works for messages received while this is on."),
            KimogramPageSection(header: ru ? "ЗАЩИЩЁННОЕ" : "PROTECTED", rows: [
                .toggle(.saveProtected, title: ru ? "Сохранять защищённое" : "Save Protected Content", text: ru ? "Копировать, сохранять и снимать скриншоты где запрещено, сохранять чужие истории" : "Copy, save and screenshot where it is restricted; save others' stories")
            ], footer: ru ? "Переслать такое сообщение всё равно нельзя: это запрещает сервер. Сохраните или скопируйте его." : "Forwarding stays blocked by the server; save or copy instead.")
        ]
    })
}

private func chatsPage(context: AccountContext) -> ViewController {
    let ru = KimogramAutoProxy.isRussian
    return kimogramPageController(context: context, title: ru ? "Сообщения и чаты" : "Messages and Chats", build: { _ in
        return [
            KimogramPageSection(header: ru ? "ЖЕСТЫ И МЕНЮ" : "GESTURES AND MENU", rows: [
                .toggle(.extendedMessageMenu, title: ru ? "Расширенное меню" : "Extended Menu", text: ru ? "Повторить, В Избранное, ID и точное время" : "Repeat, Save to Favourites, ID and exact time"),
                .link(title: ru ? "Двойное касание" : "Double Tap", icon: nil, label: doubleTapTitles(ru)[KimogramSettings.doubleTapAction.rawValue], action: { environment in
                    environment.push(kimogramChoiceController(context: environment.context, title: ru ? "Двойное касание" : "Double Tap", footer: ru ? "Что делает двойное касание по сообщению." : "What a double tap on a message does.", options: doubleTapTitles(ru), selected: {
                        return KimogramSettings.doubleTapAction.rawValue
                    }, select: { index in
                        KimogramSettings.doubleTapAction = KimogramSettings.DoubleTapAction(rawValue: index) ?? .reaction
                    }))
                }),
                .toggle(.disableSwipeReply, title: ru ? "Выключить свайп для ответа" : "Disable Swipe to Reply", text: nil)
            ]),
            KimogramPageSection(header: ru ? "ЗАЩИТА ОТ СЛУЧАЙНОСТЕЙ" : "NO ACCIDENTS", rows: [
                .toggle(.confirmStickers, title: ru ? "Спрашивать перед стикером и GIF" : "Confirm Stickers and GIFs", text: nil),
                .toggle(.confirmVoice, title: ru ? "Прослушать голосовое перед отправкой" : "Review Voice Before Sending", text: ru ? "Отпустили кнопку — сначала прослушивание" : "Releasing the button opens a preview"),
                .toggle(.confirmCalls, title: ru ? "Спрашивать перед звонком" : "Confirm Before Calling", text: nil)
            ]),
            KimogramPageSection(header: ru ? "ЛЕНТА" : "FEED", rows: [
                .toggle(.hideSponsored, title: ru ? "Без рекламы в каналах" : "No Sponsored Messages", text: nil),
                .toggle(.timestampSeconds, title: ru ? "Время с секундами" : "Show Seconds in Time", text: nil),
                .toggle(.hideStoriesBar, title: ru ? "Скрыть истории над чатами" : "Hide Stories Row", text: nil),
                .toggle(.hideReactions, title: ru ? "Скрыть реакции" : "Hide Reactions", text: ru ? "Под сообщениями не будет реакций" : "No reactions under messages"),
                .toggle(.hideSimilarChannels, title: ru ? "Скрыть похожие каналы" : "Hide Similar Channels", text: nil),
                .toggle(.hideShareButton, title: ru ? "Без кнопки «Поделиться» у постов" : "No Share Button on Posts", text: nil),
                .toggle(.openLinksDirectly, title: ru ? "Открывать ссылки без вопроса" : "Open Links Without Asking", text: ru ? "Даже если текст ссылки не совпадает с адресом" : "Even when the link text differs from the address")
            ])
        ]
    })
}

private func profilePage(context: AccountContext) -> ViewController {
    let ru = KimogramAutoProxy.isRussian
    return kimogramPageController(context: context, title: ru ? "Профиль" : "Profile", build: { _ in
        return [
            KimogramPageSection(header: ru ? "ЧУЖИЕ ПРОФИЛИ" : "OTHER PROFILES", rows: [
                .toggle(.showPeerId, title: ru ? "Показывать ID" : "Show ID", text: ru ? "Нажмите на ID, чтобы скопировать" : "Tap the ID to copy it")
            ]),
            KimogramPageSection(header: ru ? "МОИ НАСТРОЙКИ" : "MY SETTINGS", rows: [
                .toggle(.hidePhoneNumber, title: ru ? "Скрыть мой номер" : "Hide My Number", text: ru ? "Удобно для скриншотов" : "Keeps it off screenshots"),
                .toggle(.hidePremiumRows, title: ru ? "Скрыть Premium и подарки" : "Hide Premium and Gifts", text: ru ? "В настройках и кнопка подарка в чатах" : "In Settings, and the gift button in chats")
            ])
        ]
    })
}

private func stickerSizeTitles(_ ru: Bool) -> [String] {
    return ru ? ["Обычные", "Маленькие", "Средние", "Крупные"] : ["Normal", "Small", "Medium", "Large"]
}

private func appearancePage(context: AccountContext) -> ViewController {
    let ru = KimogramAutoProxy.isRussian
    return kimogramPageController(context: context, title: ru ? "Оформление" : "Appearance", build: { _ in
        return [
            KimogramPageSection(header: ru ? "ИНТЕРФЕЙС" : "INTERFACE", rows: [
                .toggle(.hideContactsTab, title: ru ? "Скрыть вкладку «Контакты»" : "Hide Contacts Tab", text: ru ? "Вкладку «Звонки» скрывают в Настройки ▸ Недавние звонки" : "Calls tab: Settings ▸ Recent Calls"),
                .toggle(.hidePremiumBadges, title: ru ? "Скрыть значки Premium" : "Hide Premium Badges", text: ru ? "Звёзды и эмодзи-статусы у имён" : "Stars and emoji statuses next to names"),
                .toggle(.hideFolderBadges, title: ru ? "Без счётчиков у папок" : "No Folder Counters", text: ru ? "Цифры непрочитанных на вкладках папок" : "Unread numbers on folder tabs"),
                .link(title: ru ? "Размер стикеров" : "Sticker Size", icon: nil, label: stickerSizeTitles(ru)[KimogramSettings.stickerSize.rawValue], action: { environment in
                    environment.push(kimogramChoiceController(context: environment.context, title: ru ? "Размер стикеров" : "Sticker Size", footer: ru ? "Размер стикеров и больших эмодзи в чатах. Применяется к новым и открытым заново чатам." : "Size of stickers and large emoji in chats. Applies when a chat is opened again.", options: stickerSizeTitles(ru), selected: {
                        return KimogramSettings.stickerSize.rawValue
                    }, select: { index in
                        KimogramSettings.stickerSize = KimogramSettings.StickerSize(rawValue: index) ?? .normal
                    }))
                })
            ]),
            KimogramPageSection(rows: [
                .link(title: ru ? "Тема и иконка приложения" : "Theme and App Icon", icon: PresentationResourcesSettings.appearance, label: "", action: { environment in
                    environment.push(themeSettingsController(context: environment.context))
                })
            ], footer: ru ? "Фиолетовая тема Kimogram стоит первой в списке цветов, там же варианты иконки." : "The violet Kimogram colours come first in the colour list, next to the Kimogram icons.")
        ]
    })
}

public func kimogramSettingsController(context: AccountContext) -> ViewController {
    let ru = KimogramAutoProxy.isRussian
    return kimogramPageController(context: context, title: kimogramSettingsTitle(), build: { autoProxyEnabled in
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return [
            KimogramPageSection(rows: [
                .hero(title: "Kimogram", subtitle: ru ? "Привычный мессенджер, только мощнее и красивее" : "The messenger you know, more powerful and beautiful")
            ]),
            KimogramPageSection(header: ru ? "ПОДКЛЮЧЕНИЕ" : "CONNECTION", rows: [
                .link(title: ru ? "Прокси" : "Proxy", icon: PresentationResourcesSettings.proxy, label: autoProxyEnabled ? (ru ? "Авто" : "Auto") : (ru ? "Свой" : "Manual"), action: { environment in
                    environment.push(proxySettingsController(context: environment.context))
                }),
                .toggle(.fastDownloads, title: ru ? "Быстрая загрузка и отправка" : "Faster Transfers", text: ru ? "Больше потоков для скачивания и отправки файлов" : "More parallel parts for downloads and uploads")
            ], footer: ru ? "Авто-прокси сам находит рабочий бесплатный прокси, если подключиться не получается." : "Auto Proxy finds a working free proxy whenever the app cannot connect."),
            KimogramPageSection(header: ru ? "ПРИВАТНОСТЬ" : "PRIVACY", rows: [
                .link(title: ru ? "Режим призрака" : "Ghost Mode", icon: PresentationResourcesSettings.security, label: countLabel(ghostKeys, ru), action: { environment in
                    environment.push(ghostPage(context: environment.context))
                }),
                .link(title: ru ? "Сохранение" : "Keep History", icon: PresentationResourcesSettings.savedMessages, label: countLabel(historyKeys, ru), action: { environment in
                    environment.push(historyPage(context: environment.context))
                })
            ], footer: ru ? "Любой чат можно закрыть Face ID: зажмите его в списке чатов и выберите «Заблокировать чат». Сейчас заблокировано: \(KimogramSettings.lockedChatCount)." : "Any chat can be locked with Face ID: press and hold it in the chat list and choose Lock Chat. Locked now: \(KimogramSettings.lockedChatCount)."),
            KimogramPageSection(header: ru ? "УДОБСТВО" : "COMFORT", rows: [
                .link(title: ru ? "Сообщения и чаты" : "Messages and Chats", icon: PresentationResourcesSettings.privateChats, label: "", action: { environment in
                    environment.push(chatsPage(context: environment.context))
                }),
                .link(title: ru ? "Профиль" : "Profile", icon: PresentationResourcesSettings.myProfile, label: "", action: { environment in
                    environment.push(profilePage(context: environment.context))
                }),
                .link(title: ru ? "Оформление" : "Appearance", icon: PresentationResourcesSettings.appearance, label: "", action: { environment in
                    environment.push(appearancePage(context: environment.context))
                })
            ], footer: ru ? "Kimogram \(version) (\(build)). Основан на открытом коде Telegram для iOS." : "Kimogram \(version) (\(build)). Built on the open-source Telegram for iOS.")
        ]
    })
}
