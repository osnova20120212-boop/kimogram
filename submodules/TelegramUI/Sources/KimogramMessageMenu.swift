import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import ContextUI
import UndoUI
import ChatControllerInteraction
import PresentationDataUtils

/// Kimogram: the extra rows of a message's long-press menu.
///
/// Repeat sends the message again into the same chat without the "Forwarded from" header,
/// Save to Favourites forwards it to Saved Messages in one tap, and the last row shows the exact
/// time it was sent (and edited), copying it on tap.
func kimogramMessageMenuItems(context: AccountContext, message: EngineRawMessage, chatLocation: ChatLocation, isCopyProtected: Bool, controllerInteraction: ChatControllerInteraction) -> [ContextMenuItem] {
    guard KimogramSettings.get(.extendedMessageMenu) else {
        return []
    }
    guard message.id.namespace == Namespaces.Message.Cloud, message.id.peerId.namespace != Namespaces.Peer.SecretChat else {
        return []
    }
    if message.media.contains(where: { $0 is TelegramMediaAction }) {
        return []
    }

    let ru = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode == "ru"
    var items: [ContextMenuItem] = []

    var threadId: Int64?
    if case let .replyThread(replyThreadMessage) = chatLocation {
        threadId = replyThreadMessage.threadId
    }

    if !isCopyProtected {
        items.append(.action(ContextMenuActionItem(text: ru ? "Повторить" : "Repeat", icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Resend"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            f(.default)
            let attributes: [EngineMessage.Attribute] = [ForwardOptionsMessageAttribute(hideNames: true, hideCaptions: false)]
            let _ = enqueueMessages(account: context.account, peerId: message.id.peerId, messages: [.forward(source: message.id, threadId: threadId, grouping: .auto, attributes: attributes, correlationId: nil)]).startStandalone()
        })))

        if message.id.peerId != context.account.peerId {
            items.append(.action(ContextMenuActionItem(text: ru ? "В Избранное" : "Save to Favourites", icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Fave"), color: theme.actionSheet.primaryTextColor)
            }, action: { _, f in
                f(.default)
                let _ = enqueueMessages(account: context.account, peerId: context.account.peerId, messages: [.forward(source: message.id, threadId: nil, grouping: .auto, attributes: [], correlationId: nil)]).startStandalone()
                Queue.mainQueue().after(0.2) {
                    controllerInteraction.displayUndo(.forward(savedMessages: true, text: ru ? "Сохранено в Избранное" : "Saved to Favourites"))
                }
            })))
        }
    }

    // In a group, write to the author privately in one tap.
    if message.id.peerId.namespace != Namespaces.Peer.CloudUser, let author = message.author as? TelegramUser, author.id != context.account.peerId, author.botInfo == nil {
        items.append(.action(ContextMenuActionItem(text: ru ? "Написать автору" : "Message Author", icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Message"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            f(.dismissWithoutContent)
            controllerInteraction.openPeer(EnginePeer(author), .chat(textInputState: nil, subject: nil, peekData: nil), nil, .default)
        })))
    }

    // Earlier versions of an edited message, kept by "Keep Edit History".
    if let history = kimogramEditHistoryText(message.text, ru: ru) {
        items.append(.action(ContextMenuActionItem(text: ru ? "История правок" : "Edit History", icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Edit"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            f(.dismissWithoutContent)
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            controllerInteraction.presentController(textAlertController(context: context, title: ru ? "История правок" : "Edit History", text: history, actions: [
                TextAlertAction(type: .genericAction, title: ru ? "Скопировать" : "Copy", action: {
                    UIPasteboard.general.string = history
                }),
                TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
            ]), nil)
        })))
    }

    items.append(.action(ContextMenuActionItem(text: ru ? "Скопировать ID" : "Copy ID", icon: { theme in
        return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Copy"), color: theme.actionSheet.primaryTextColor)
    }, action: { _, f in
        f(.default)
        UIPasteboard.general.string = "\(message.id.id)"
        Queue.mainQueue().after(0.2) {
            controllerInteraction.displayUndo(.copy(text: ru ? "ID сообщения скопирован" : "Message ID copied"))
        }
    })))

    let formatter = DateFormatter()
    formatter.dateFormat = "dd.MM.yyyy HH:mm:ss"
    let sentText = (ru ? "Отправлено " : "Sent ") + formatter.string(from: Date(timeIntervalSince1970: TimeInterval(message.timestamp)))
    var editedText: String?
    for attribute in message.attributes {
        if let attribute = attribute as? EditedMessageAttribute, !attribute.isHidden {
            editedText = (ru ? "Изменено " : "Edited ") + formatter.string(from: Date(timeIntervalSince1970: TimeInterval(attribute.date)))
        }
    }
    let fullText = editedText.flatMap { sentText + "\n" + $0 } ?? sentText
    items.append(.action(ContextMenuActionItem(text: fullText, textLayout: .multiline, textFont: .small, icon: { theme in
        return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Time"), color: theme.actionSheet.primaryTextColor)
    }, action: { _, f in
        f(.default)
        UIPasteboard.general.string = fullText
        Queue.mainQueue().after(0.2) {
            controllerInteraction.displayUndo(.copy(text: ru ? "Время скопировано" : "Time copied"))
        }
    })))

    return items
}

/// The part of a message's text that "Keep Edit History" appended: every earlier version, without
/// the "deleted" note. Nil when the message was never edited while the switch was on.
private func kimogramEditHistoryText(_ text: String, ru: Bool) -> String? {
    var start: Range<String.Index>?
    for marker in ["\n\n✏️ Было:", "\n\n✏️ Was:"] {
        if let range = text.range(of: marker) {
            start = range
            break
        }
    }
    guard let start else {
        return nil
    }
    let current = String(text[text.startIndex ..< start.lowerBound])
    var history = String(text[text.index(start.lowerBound, offsetBy: 2)...])
    for marker in ["🗑 Удалено", "🗑 Deleted"] {
        if history.hasSuffix(marker) {
            history = String(history.dropLast(marker.count))
        }
    }
    history = history.trimmingCharacters(in: .whitespacesAndNewlines)
    if history.isEmpty {
        return nil
    }
    if current.isEmpty {
        return history
    }
    return history + "\n\n" + (ru ? "✅ Сейчас:" : "✅ Now:") + "\n" + current
}
