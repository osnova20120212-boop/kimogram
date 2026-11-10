import Foundation
import UIKit
import Display
import AccountContext
import PresentationDataUtils
import TelegramCore

/// Kimogram: "What's new" once after every update.
enum KimogramWhatsNew {
    private static let seenBuildKey = "kimogram.whatsNew.seenBuild"

    static func showIfNeeded(context: AccountContext) {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let defaults = UserDefaults.standard
        if defaults.string(forKey: seenBuildKey) == build {
            return
        }
        defaults.set(build, forKey: seenBuildKey)

        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let ru = presentationData.strings.baseLanguageCode == "ru"
        let text: String
        if KimogramSettings.storeEdition {
            // Telegram's API terms (2.2): the app must say plainly that it is an unofficial client
            // built on the Telegram API.
            text = ru ? """
            Kimogram — неофициальный клиент Telegram. Он работает через открытый Telegram API: ваши чаты, контакты и аккаунт те же, что в Telegram.

            ✨ Жидкое стекло и плавные анимации
            🎧 Трек из Яндекс Музыки в профиль
            🔒 Замок на чаты, размытие в списке приложений
            🌐 Авто-прокси, если подключиться не получается

            Все настройки: Настройки → Настройки Kimogram.
            """ : """
            Kimogram is an unofficial Telegram client. It uses the open Telegram API: your chats, contacts and account are the same as in Telegram.

            ✨ Liquid glass and smooth animations
            🎧 A Yandex Music track in your profile
            🔒 Chat locks and blur in the app switcher
            🌐 Auto Proxy when the app cannot connect

            Every setting: Settings → Kimogram Settings.
            """
        } else if ru {
            text = """
            ✨ Жидкое стекло: ползунок прозрачности, фиолетовый оттенок, спокойное стекло и классический вид
            🎧 Трек из Яндекс Музыки в профиль: скопируйте ссылку на трек
            👤 Форма аватарок и округлый шрифт
            👻 Призрак без «записывает голосовое», без «скриншот сделан» и без накрутки просмотров
            💬 В меню сообщения: цитата, ссылка, копия фото, подробности
            🔒 Размытие в списке приложений, очистка ссылок от слежки
            ⚡️ Ярлык призрака на иконке, «Прочитать все чаты», скорость до 3×

            Всё это в Настройки → Настройки Kimogram.
            """
        } else {
            text = """
            ✨ Liquid glass: transparency slider, violet tint, calm glass and classic look
            🎧 A Yandex Music track in your profile: copy a track link
            👤 Avatar shape and rounded font
            👻 Ghost mode without "recording voice", screenshot notices and view counts
            💬 Message menu: quote, link, copy photo, details
            🔒 Blur in the app switcher, tracking removed from links
            ⚡️ Ghost shortcut on the icon, Read All Chats, speed up to 3×

            All in Settings → Kimogram Settings.
            """
        }
        let controller = textAlertController(context: context, title: KimogramSettings.storeEdition ? (ru ? "Добро пожаловать в Kimogram" : "Welcome to Kimogram") : (ru ? "Что нового в Kimogram" : "What's New in Kimogram"), text: text, actions: [
            TextAlertAction(type: .defaultAction, title: ru ? "Отлично" : "Great", action: {})
        ])
        context.sharedContext.mainWindow?.present(controller, on: .root, blockInteraction: false, completion: {})
    }
}
