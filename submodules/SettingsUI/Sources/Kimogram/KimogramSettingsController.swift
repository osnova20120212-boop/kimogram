import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import TelegramUIPreferences
import AlertUI
import PromptUI

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
    /// A switch that is not one of `KimogramSettings`' keys (appearance switches live in Display).
    case flag(title: String, text: String?, value: Bool, set: (Bool) -> Void)
    /// A stepped slider with a caption under each end.
    case slider(value: Int, positions: Int, leftTitle: String, rightTitle: String, set: (Int) -> Void)
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
    var present: (ViewController) -> Void = { _ in }

    /// A short message with one OK button.
    func showAlert(title: String?, text: String) {
        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        self.present(textAlertController(context: self.context, title: title, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]))
    }

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
    case slider(Int, Int, String, String)
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
                    case let .flag(_, _, _, set):
                        set(value)
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
            case let .slider(value, positions, leftTitle, rightTitle):
                return KimogramSliderItem(theme: presentationData.theme, value: value, positions: positions, leftTitle: leftTitle, rightTitle: rightTitle, sectionId: self.section, updated: { value in
                    if let row, case let .slider(_, _, _, _, set) = row {
                        set(value)
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
            case let .flag(title, text, value, _):
                kind = .toggle(title, text, value)
            case let .slider(value, positions, leftTitle, rightTitle, _):
                kind = .slider(value, positions, leftTitle, rightTitle)
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

    let signal = combineLatest(queue: Queue.mainQueue(), context.sharedContext.presentationData, KimogramSettings.changes(), KimogramAutoProxy.shared.enabled, kimogramAppearanceChanges())
    |> map { presentationData, _, autoProxyEnabled, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
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
    environment.present = { [weak controller] c in
        controller?.present(c, in: .window(.root), with: nil)
    }
    return controller
}

/// Fires once at start and on every change of the Display-level appearance switches.
func kimogramAppearanceChanges() -> Signal<Int, NoError> {
    return Signal { subscriber in
        subscriber.putNext(KimogramAppearance.generation)
        let observer = NotificationCenter.default.addObserver(forName: KimogramAppearance.didChangeNotification, object: nil, queue: OperationQueue.main, using: { _ in
            subscriber.putNext(KimogramAppearance.generation)
        })
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
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
            KimogramPageSection(header: ru ? "ПО РАСПИСАНИЮ" : "SCHEDULE", rows: [
                .link(title: ru ? "Призрак по расписанию" : "Scheduled Ghost Mode", icon: nil, label: ghostScheduleTitles(ru)[KimogramSettings.ghostSchedule], action: { environment in
                    environment.push(kimogramChoiceController(context: environment.context, title: ru ? "Призрак по расписанию" : "Scheduled Ghost Mode", footer: ru ? "В эти часы призрак включается сам: не видно «прочитано», «в сети», «печатает», просмотров историй и прослушивания голосовых." : "During these hours ghost mode turns itself on.", options: ghostScheduleTitles(ru), selected: {
                        return KimogramSettings.ghostSchedule
                    }, select: { index in
                        KimogramSettings.ghostSchedule = index
                    }))
                })
            ], footer: KimogramSettings.ghostScheduleActiveNow ? (ru ? "Сейчас призрак включён по расписанию." : "Ghost mode is on now by the schedule.") : nil),
            KimogramPageSection(header: ru ? "ЕЩЁ НЕЗАМЕТНЕЕ" : "EVEN QUIETER", rows: [
                .toggle(.hideRecordingActivity, title: ru ? "Без «записывает голосовое»" : "Hide Recording Status", text: ru ? "И без «выбирает стикер», «отправляет фото»" : "Also choosing a sticker, sending a photo"),
                .toggle(.noScreenshotNotice, title: ru ? "Без «сделан скриншот»" : "No Screenshot Notice", text: ru ? "В секретных чатах собеседник не узнает о скриншоте" : "Secret chats won't report your screenshots"),
                .toggle(.noViewIncrement, title: ru ? "Не накручивать просмотры" : "Don't Count My Views", text: ru ? "Посты в каналах не получают ваш просмотр" : "Channel posts don't get your view")
            ]),
            KimogramPageSection(header: ru ? "ИСКЛЮЧЕНИЕ" : "EXCEPTION", rows: [
                .toggle(.ghostReadOnReply, title: ru ? "Прочитано, когда отвечаю" : "Mark Read When I Reply", text: ru ? "Ответ сам отмечает чат прочитанным" : "Replying marks the chat as read")
            ], footer: ru ? "Когда вы сами отправляете сообщение, сервер всё равно ненадолго показывает вас в сети." : "Sending a message still briefly shows you online."),
            KimogramPageSection(header: ru ? "ЧАТЫ БЕЗ ПРИЗРАКА" : "CHATS WITHOUT GHOST MODE", rows: [
                .link(title: ru ? "Чаты без призрака" : "Chats Without Ghost Mode", icon: nil, label: "\(KimogramSettings.ghostExceptionPeerIds.count)", action: { environment in
                    environment.showAlert(title: ru ? "Чаты без призрака" : "Chats Without Ghost Mode", text: ru ? "Зажмите чат в списке чатов и выберите «Без призрака в этом чате». Там собеседник будет видеть, что вы прочитали и печатаете." : "Press and hold a chat in the chat list and choose No Ghost Mode Here. That chat will see your read receipts and typing.")
                })
            ], footer: ru ? "В этих чатах призрак не действует, во всех остальных работает как обычно." : "Ghost mode does not apply in these chats.")
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
                .toggle(.disableSwipeReply, title: ru ? "Выключить свайп для ответа" : "Disable Swipe to Reply", text: nil),
                .toggle(.hideBotButtons, title: ru ? "Скрыть кнопки ботов" : "Hide Bot Buttons", text: ru ? "Кнопки под сообщениями ботов не показываются" : "Buttons under bot messages are hidden"),
                .toggle(.hideStickerButton, title: ru ? "Скрыть кнопку стикеров" : "Hide Sticker Button", text: ru ? "Убирает значок стикеров из поля ввода" : "Removes the sticker icon from the message field"),
                .toggle(.hideGiftButton, title: ru ? "Скрыть кнопку подарков" : "Hide Gift Button", text: ru ? "В поле ввода и в меню профиля" : "In the message field and the profile menu"),
                .toggle(.hidePaidReactions, title: ru ? "Скрыть платные реакции" : "Hide Paid Reactions", text: ru ? "Реакция-звезда не предлагается в меню" : "The star reaction is not offered"),
                .toggle(.charCounter, title: ru ? "Счётчик символов" : "Character Counter", text: ru ? "Показывает длину сообщения в поле ввода" : "Shows the message length in the field")
            ]),
            KimogramPageSection(header: ru ? "ОТПРАВКА" : "SENDING", rows: [
                .toggle(.silentByDefault, title: ru ? "Отправлять без звука" : "Send Silently", text: ru ? "Собеседник получит сообщение без звука уведомления" : "Recipients get no notification sound"),
                .toggle(.pinSilently, title: ru ? "Закреплять без уведомления" : "Pin Silently", text: ru ? "Без вопроса «Уведомить всех?»" : "No \"Notify all members?\" question"),
                .toggle(.noLinkPreviews, title: ru ? "Ссылки без превью" : "Links Without Preview", text: ru ? "Ссылка уходит без карточки сайта" : "Links are sent without a site card"),
                .flag(title: ru ? "Фото в высоком качестве" : "HD Photos", text: ru ? "Фото отправляются в HD сразу" : "Photos are sent in HD by default", value: UserDefaults.standard.bool(forKey: "TG_photoHighQuality_v0"), set: { value in
                    UserDefaults.standard.set(value, forKey: "TG_photoHighQuality_v0")
                }),
                .toggle(.stripTrackingParams, title: ru ? "Очищать ссылки от слежки" : "Clean Tracking from Links", text: ru ? "Убирает utm, fbclid и подобные метки из ссылок" : "Removes utm, fbclid and similar tags")
            ]),
            KimogramPageSection(header: ru ? "ЗАЩИТА ОТ СЛУЧАЙНОСТЕЙ" : "NO ACCIDENTS", rows: [
                .toggle(.confirmSend, title: ru ? "Спрашивать перед отправкой" : "Confirm Before Sending", text: ru ? "Перед каждым сообщением из поля ввода" : "Before every message from the text field"),
                .toggle(.confirmStickers, title: ru ? "Спрашивать перед стикером и GIF" : "Confirm Stickers and GIFs", text: nil),
                .toggle(.confirmVoice, title: ru ? "Прослушать голосовое перед отправкой" : "Review Voice Before Sending", text: ru ? "Отпустили кнопку — сначала прослушивание" : "Releasing the button opens a preview"),
                .toggle(.confirmCalls, title: ru ? "Спрашивать перед звонком" : "Confirm Before Calling", text: nil)
            ]),
            KimogramPageSection(header: ru ? "ЛЕНТА" : "FEED", rows: [
                .toggle(.hideSponsored, title: ru ? "Без рекламы в каналах" : "No Sponsored Messages", text: nil),
                .toggle(.timestampSeconds, title: ru ? "Время с секундами" : "Show Seconds in Time", text: nil),
                .toggle(.hideStoriesBar, title: ru ? "Скрыть истории над чатами" : "Hide Stories Row", text: nil),
                .toggle(.hideStoryCamera, title: ru ? "Скрыть кнопку камеры историй" : "Hide Story Camera Button", text: nil),
                .toggle(.noChatListSeparators, title: ru ? "Без линий между чатами" : "No Lines Between Chats", text: nil),
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
            ]),
            KimogramPageSection(header: ru ? "МУЗЫКА В ПРОФИЛЕ" : "MUSIC IN PROFILE", rows: [
                .flag(title: ru ? "Трек из Яндекс Музыки" : "Yandex Music Track", text: ru ? "Предлагать добавить скопированный трек в профиль" : "Offer to add a copied track to the profile", value: !KimogramSettings.get(.noMusicCard), set: { value in
                    KimogramSettings.set(.noMusicCard, !value)
                })
            ], footer: ru ? "В Яндекс Музыке нажмите «Поделиться» → «Скопировать ссылку» и вернитесь в Kimogram: появится карточка «Добавить трек в профиль?». Трек встанет в описание профиля." : "In Yandex Music tap Share → Copy Link and come back to Kimogram: a card offers to add the track to your profile bio.")
        ]
    })
}

private func ghostScheduleTitles(_ ru: Bool) -> [String] {
    return KimogramSettings.ghostSchedules.enumerated().map { index, item in
        if index == 0 {
            return ru ? "Выключено" : "Off"
        }
        return String(format: "%02d:00 – %02d:00", item.from, item.to)
    }
}

private func avatarShapeTitles(_ ru: Bool) -> [String] {
    return ru ? ["Круг", "Скруглённый квадрат", "Квадрат"] : ["Circle", "Rounded Square", "Square"]
}

private func bubbleWidthTitles(_ ru: Bool) -> [String] {
    return ru ? ["Обычная", "Узкая", "Широкая"] : ["Normal", "Narrow", "Wide"]
}

private func roundVideoTitles(_ ru: Bool) -> [String] {
    return ru ? ["Обычный", "Большой"] : ["Normal", "Large"]
}

private func stickerSizeTitles(_ ru: Bool) -> [String] {
    return ru ? ["Обычные", "Маленькие", "Средние", "Крупные"] : ["Normal", "Small", "Medium", "Large"]
}

private func appearancePage(context: AccountContext) -> ViewController {
    let ru = KimogramAutoProxy.isRussian
    return kimogramPageController(context: context, title: ru ? "Оформление" : "Appearance", build: { _ in
        let glassStep = Int((KimogramAppearance.glassTransparency * 10.0).rounded())
        return [
            KimogramPageSection(header: ru ? "ЖИДКОЕ СТЕКЛО" : "LIQUID GLASS", rows: [
                .slider(value: glassStep, positions: 11, leftTitle: ru ? "Матовое" : "Matte", rightTitle: ru ? "Прозрачное" : "Clear", set: { value in
                    let updated = CGFloat(value) / 10.0
                    if abs(updated - KimogramAppearance.glassTransparency) > 0.001 {
                        KimogramAppearance.glassTransparency = updated
                    }
                }),
                .flag(title: ru ? "Фиолетовый оттенок" : "Violet Tint", text: ru ? "Стекло в цвет Kimogram" : "Glass in Kimogram's colour", value: KimogramAppearance.glassTint, set: { value in
                    KimogramAppearance.glassTint = value
                }),
                .flag(title: ru ? "Спокойное стекло" : "Calm Glass", text: ru ? "Кнопки не растягиваются и не переливаются под пальцем" : "Buttons don't stretch and shimmer under a finger", value: KimogramAppearance.glassStatic, set: { value in
                    KimogramAppearance.glassStatic = value
                }),
                .flag(title: ru ? "Без размытия под меню" : "No Blur Behind Menus", text: ru ? "Фон за меню по долгому нажатию остаётся чётким" : "The screen stays sharp behind long-press menus", value: KimogramAppearance.noMenuBlur, set: { value in
                    KimogramAppearance.noMenuBlur = value
                }),
                .flag(title: ru ? "Классический вид" : "Classic Look", text: ru ? "Сплошные панели вместо стекла, как в старом Telegram" : "Solid panels instead of glass, like the old Telegram", value: KimogramAppearance.classicPanels, set: { value in
                    KimogramAppearance.classicPanels = value
                })
            ], footer: ru ? "Ползунок меняет стекло везде: панели, кнопки, меню и поле ввода. Середина — как в обычном Telegram." : "The slider changes the glass everywhere: bars, buttons, menus and the input field. The middle is Telegram's own look."),
            KimogramPageSection(header: ru ? "ИНТЕРФЕЙС" : "INTERFACE", rows: [
                .toggle(.hideContactsTab, title: ru ? "Скрыть вкладку «Контакты»" : "Hide Contacts Tab", text: nil),
                .link(title: ru ? "Форма аватарок" : "Avatar Shape", icon: nil, label: avatarShapeTitles(ru)[KimogramAppearance.avatarShape.rawValue], action: { environment in
                    environment.push(kimogramChoiceController(context: environment.context, title: ru ? "Форма аватарок" : "Avatar Shape", footer: ru ? "Применяется полностью после перезапуска Kimogram." : "Fully applies after restarting Kimogram.", options: avatarShapeTitles(ru), selected: {
                        return KimogramAppearance.avatarShape.rawValue
                    }, select: { index in
                        KimogramAppearance.avatarShape = KimogramAppearance.AvatarShape(rawValue: index) ?? .circle
                    }))
                }),
                .flag(title: ru ? "Округлый шрифт" : "Rounded Font", text: ru ? "SF Rounded во всём приложении, после перезапуска" : "SF Rounded everywhere, after a restart", value: KimogramAppearance.roundedFont, set: { value in
                    KimogramAppearance.roundedFont = value
                }),
                .flag(title: ru ? "Без вибрации" : "No Vibration", text: ru ? "Кнопки и жесты без отклика вибрацией" : "No haptic feedback on buttons and gestures", value: KimogramAppearance.noHaptics, set: { value in
                    KimogramAppearance.noHaptics = value
                }),
                .toggle(.hideHelpSection, title: ru ? "Скрыть «Помощь» в настройках" : "Hide Help in Settings", text: ru ? "«Задать вопрос», «Вопросы и ответы», «Возможности»" : "Ask a Question, FAQ, Features"),
                .link(title: ru ? "Вкладка «Звонки»" : "Calls Tab", icon: nil, label: "", action: { environment in
                    let accountManager = environment.context.sharedContext.accountManager
                    let _ = (accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.callListSettings])
                    |> take(1)
                    |> deliverOnMainQueue).startStandalone(next: { sharedData in
                        var shown = CallListSettings.defaultSettings.showTab
                        if let settings = sharedData.entries[ApplicationSpecificSharedDataKeys.callListSettings]?.get(CallListSettings.self) {
                            shown = settings.showTab
                        }
                        environment.push(kimogramChoiceController(context: environment.context, title: ru ? "Вкладка «Звонки»" : "Calls Tab", footer: ru ? "Вкладка со списком звонков внизу экрана." : "The calls list tab at the bottom of the screen.", options: ru ? ["Показывать", "Скрыть"] : ["Show", "Hide"], selected: {
                            return shown ? 0 : 1
                        }, select: { index in
                            shown = index == 0
                            let _ = updateCallListSettingsInteractively(accountManager: accountManager, { settings in
                                var settings = settings
                                settings.showTab = index == 0
                                return settings
                            }).startStandalone()
                        }))
                    })
                }),
                .toggle(.hidePremiumBadges, title: ru ? "Скрыть значки Premium" : "Hide Premium Badges", text: ru ? "Звёзды и эмодзи-статусы у имён" : "Stars and emoji statuses next to names"),
                .toggle(.hideFolderBadges, title: ru ? "Без счётчиков у папок" : "No Folder Counters", text: ru ? "Цифры непрочитанных на вкладках папок" : "Unread numbers on folder tabs"),
                .toggle(.hideChatsTabBadge, title: ru ? "Без счётчика на вкладке «Чаты»" : "No Counter on Chats Tab", text: nil),
                .toggle(.hideAppIconBadge, title: ru ? "Без цифры на иконке" : "No Number on App Icon", text: ru ? "Цифра пропадает, когда вы открываете Kimogram" : "Clears whenever you open Kimogram"),
                .link(title: ru ? "Название над чатами" : "Chat List Title", icon: nil, label: KimogramSettings.customChatListTitle ?? "Kimogram", action: { environment in
                    environment.present(promptController(context: environment.context, text: ru ? "Название над списком чатов" : "Title above the chat list", value: KimogramSettings.customChatListTitle, placeholder: "Kimogram", characterLimit: 24, displayCharacterLimit: true, apply: { value in
                        if let value {
                            KimogramSettings.customChatListTitle = value
                        }
                    }))
                }),
                .toggle(.titleAccountName, title: ru ? "Моё имя вместо «Kimogram»" : "My Name as the Title", text: ru ? "В шапке списка чатов" : "Above the chat list"),
                .toggle(.hideEditButton, title: ru ? "Скрыть кнопку «Изменить»" : "Hide Edit Button", text: ru ? "Над списком чатов" : "Above the chat list"),
                .link(title: ru ? "Размер стикеров" : "Sticker Size", icon: nil, label: stickerSizeTitles(ru)[KimogramSettings.stickerSize.rawValue], action: { environment in
                    environment.push(kimogramChoiceController(context: environment.context, title: ru ? "Размер стикеров" : "Sticker Size", footer: ru ? "Размер стикеров и больших эмодзи в чатах. Применяется к новым и открытым заново чатам." : "Size of stickers and large emoji in chats. Applies when a chat is opened again.", options: stickerSizeTitles(ru), selected: {
                        return KimogramSettings.stickerSize.rawValue
                    }, select: { index in
                        KimogramSettings.stickerSize = KimogramSettings.StickerSize(rawValue: index) ?? .normal
                    }))
                }),
                .link(title: ru ? "Ширина сообщений" : "Bubble Width", icon: nil, label: bubbleWidthTitles(ru)[KimogramSettings.bubbleWidth], action: { environment in
                    environment.push(kimogramChoiceController(context: environment.context, title: ru ? "Ширина сообщений" : "Bubble Width", footer: ru ? "Насколько широкими бывают пузыри сообщений. Применяется к открытым заново чатам." : "How wide message bubbles can get. Applies when a chat is opened again.", options: bubbleWidthTitles(ru), selected: {
                        return KimogramSettings.bubbleWidth
                    }, select: { index in
                        KimogramSettings.bubbleWidth = index
                    }))
                }),
                .link(title: ru ? "Размер кружков" : "Round Video Size", icon: nil, label: roundVideoTitles(ru)[KimogramSettings.roundVideoSize], action: { environment in
                    environment.push(kimogramChoiceController(context: environment.context, title: ru ? "Размер кружков" : "Round Video Size", footer: ru ? "Размер видеосообщений-кружков в чатах." : "Size of round video messages in chats.", options: roundVideoTitles(ru), selected: {
                        return KimogramSettings.roundVideoSize
                    }, select: { index in
                        KimogramSettings.roundVideoSize = index
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
                .toggle(.blurInAppSwitcher, title: ru ? "Размывать в списке приложений" : "Blur in App Switcher", text: ru ? "Чужие не увидят переписку при переключении приложений" : "Nobody sees your chats when switching apps"),
                .flag(title: ru ? "Предупреждать о подозрительных ссылках" : "Warn About Suspicious Links", text: ru ? "Спросит перед открытием поддельного адреса или голого IP" : "Asks before opening a look-alike address or a bare IP", value: !KimogramSettings.get(.noSuspiciousLinkWarning), set: { value in
                    KimogramSettings.set(.noSuspiciousLinkWarning, !value)
                }),
                .link(title: ru ? "Режим призрака" : "Ghost Mode", icon: PresentationResourcesSettings.security, label: countLabel(ghostKeys, ru), action: { environment in
                    environment.push(ghostPage(context: environment.context))
                }),
                .link(title: ru ? "Сохранение" : "Keep History", icon: PresentationResourcesSettings.savedMessages, label: countLabel(historyKeys, ru), action: { environment in
                    environment.push(historyPage(context: environment.context))
                }),
                .link(title: ru ? "Статистика" : "Statistics", icon: nil, label: "\(KimogramSettings.statValue(.deletedKept) + KimogramSettings.statValue(.editsKept))", action: { environment in
                    environment.showAlert(title: ru ? "Статистика Kimogram" : "Kimogram Statistics", text: ru ? "Сохранено удалённых сообщений: \(KimogramSettings.statValue(.deletedKept))\nСохранено правок: \(KimogramSettings.statValue(.editsKept))\nЗаблокировано чатов: \(KimogramSettings.lockedChatCount)\nЧатов без призрака: \(KimogramSettings.ghostExceptionPeerIds.count)" : "Deleted messages kept: \(KimogramSettings.statValue(.deletedKept))\nEdits kept: \(KimogramSettings.statValue(.editsKept))\nLocked chats: \(KimogramSettings.lockedChatCount)\nChats without ghost mode: \(KimogramSettings.ghostExceptionPeerIds.count)")
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
            ]),
            KimogramPageSection(header: ru ? "НАСТРОЙКИ KIMOGRAM" : "KIMOGRAM SETTINGS", rows: [
                .link(title: ru ? "Скопировать настройки" : "Copy Settings", icon: nil, label: "", action: { environment in
                    UIPasteboard.general.string = KimogramSettings.exportedText()
                    environment.showAlert(title: nil, text: ru ? "Настройки скопированы. Сохраните текст, например, в Избранное, чтобы потом вставить их обратно." : "Settings copied. Keep the text, for example in Saved Messages, to paste them back later.")
                }),
                .link(title: ru ? "Вставить настройки" : "Paste Settings", icon: nil, label: "", action: { environment in
                    let ok = KimogramSettings.importText(UIPasteboard.general.string ?? "")
                    environment.showAlert(title: nil, text: ok ? (ru ? "Настройки применены." : "Settings applied.") : (ru ? "Сначала скопируйте текст настроек Kimogram, он начинается с KIMOGRAM:" : "Copy Kimogram settings text first; it starts with KIMOGRAM:"))
                }),
                .link(title: ru ? "Рассказать другу" : "Tell a Friend", icon: nil, label: "", action: { environment in
                    UIPasteboard.general.string = ru ? "Попробуй Kimogram — мессенджер на основе Telegram с режимом призрака, сохранением удалённых сообщений и красивым жидким стеклом: https://github.com/osnova20120212-boop/kimogram" : "Try Kimogram, a Telegram-based messenger with ghost mode, kept deleted messages and beautiful liquid glass: https://github.com/osnova20120212-boop/kimogram"
                    environment.showAlert(title: nil, text: ru ? "Приглашение скопировано. Вставьте его в чат с другом." : "Invitation copied. Paste it into a chat with a friend.")
                }),
                .link(title: ru ? "Сбросить все настройки" : "Reset All Settings", icon: nil, label: "", action: { environment in
                    let presentationData = environment.context.sharedContext.currentPresentationData.with { $0 }
                    environment.present(textAlertController(context: environment.context, title: ru ? "Сбросить настройки Kimogram?" : "Reset Kimogram Settings?", text: ru ? "Все переключатели Kimogram вернутся к начальным. Заблокированные чаты останутся заблокированными." : "Every Kimogram switch goes back to its default. Locked chats stay locked.", actions: [
                        TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                        TextAlertAction(type: .destructiveAction, title: ru ? "Сбросить" : "Reset", action: {
                            KimogramSettings.resetAll()
                            KimogramAppearance.glassTransparency = 0.5
                            UserDefaults.standard.removeObject(forKey: "kimogram.appearance.glassTransparency")
                        })
                    ]))
                })
            ], footer: ru ? "Kimogram \(version) (\(build)). Основан на открытом коде Telegram для iOS." : "Kimogram \(version) (\(build)). Built on the open-source Telegram for iOS.")
        ]
    })
}
