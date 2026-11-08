import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import Postbox
import AccountContext
import ContextUI
import UndoUI
import ChatControllerInteraction
import PresentationDataUtils
import LocalizedPeerData

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

    if !isCopyProtected && !message.text.isEmpty {
        let plainText = kimogramEditHistoryText(message.text, ru: ru) != nil ? kimogramCurrentText(message.text) : message.text
        // Plain text, without bold, links or custom emoji.
        items.append(.action(ContextMenuActionItem(text: ru ? "Скопировать без форматирования" : "Copy as Plain Text", icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Copy"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            f(.default)
            UIPasteboard.general.string = plainText
            Queue.mainQueue().after(0.2) {
                controllerInteraction.displayUndo(.copy(text: ru ? "Текст скопирован" : "Text copied"))
            }
        })))
        // The text in quotes with its author and date.
        items.append(.action(ContextMenuActionItem(text: ru ? "Скопировать как цитату" : "Copy as Quote", icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Quote"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            f(.default)
            let quoteFormatter = DateFormatter()
            quoteFormatter.dateFormat = "dd.MM.yyyy"
            var authorName = message.author.flatMap { EnginePeer($0).compactDisplayTitle } ?? ""
            if authorName.isEmpty, let peer = message.peers[message.id.peerId] {
                authorName = EnginePeer(peer).compactDisplayTitle
            }
            var quote = "«" + plainText + "»"
            if !authorName.isEmpty {
                quote += "\n— " + authorName + ", " + quoteFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(message.timestamp)))
            }
            UIPasteboard.general.string = quote
            Queue.mainQueue().after(0.2) {
                controllerInteraction.displayUndo(.copy(text: ru ? "Цитата скопирована" : "Quote copied"))
            }
        })))
    }

    // A link to the message, also in private groups and channels (t.me/c/…), which only members can open.
    if message.id.peerId.namespace == Namespaces.Peer.CloudChannel {
        var link = ""
        if let channel = message.peers[message.id.peerId] as? TelegramChannel, let username = channel.addressName, !username.isEmpty {
            link = "https://t.me/\(username)/\(message.id.id)"
        } else {
            link = "https://t.me/c/\(message.id.peerId.id._internalGetInt64Value())/\(message.id.id)"
        }
        items.append(.action(ContextMenuActionItem(text: ru ? "Ссылка на сообщение" : "Message Link", icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Link"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            f(.default)
            UIPasteboard.general.string = link
            Queue.mainQueue().after(0.2) {
                controllerInteraction.displayUndo(.copy(text: ru ? "Ссылка скопирована" : "Link copied"))
            }
        })))
    }

    // A photo straight to the clipboard, to paste anywhere.
    if !isCopyProtected, let image = message.media.first(where: { $0 is TelegramMediaImage }) as? TelegramMediaImage, let representation = largestImageRepresentation(image.representations) {
        items.append(.action(ContextMenuActionItem(text: ru ? "Скопировать фото" : "Copy Photo", icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Copy"), color: theme.actionSheet.primaryTextColor)
        }, action: { _, f in
            f(.default)
            let _ = (context.account.postbox.mediaBox.resourceData(representation.resource, option: .complete(waitUntilFetchStatus: false))
            |> filter { $0.complete }
            |> take(1)
            |> deliverOnMainQueue).startStandalone(next: { data in
                if let photo = UIImage(contentsOfFile: data.path) {
                    UIPasteboard.general.image = photo
                    controllerInteraction.displayUndo(.copy(text: ru ? "Фото скопировано" : "Photo copied"))
                }
            })
            let _ = fetchedMediaResource(mediaBox: context.account.postbox.mediaBox, userLocation: .peer(message.id.peerId), userContentType: .image, reference: .standalone(resource: representation.resource)).startStandalone()
        })))
    }

    // Everything known about the message in one window.
    items.append(.action(ContextMenuActionItem(text: ru ? "Подробности" : "Details", icon: { theme in
        return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Info"), color: theme.actionSheet.primaryTextColor)
    }, action: { _, f in
        f(.dismissWithoutContent)
        let detailsText = kimogramMessageDetails(message: message, ru: ru)
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controllerInteraction.presentController(textAlertController(context: context, title: ru ? "Подробности" : "Details", text: detailsText, actions: [
            TextAlertAction(type: .genericAction, title: ru ? "Скопировать" : "Copy", action: {
                UIPasteboard.general.string = detailsText
            }),
            TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
        ]), nil)
    })))

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

/// The message text without what "Keep Edit History" appended.
private func kimogramCurrentText(_ text: String) -> String {
    for marker in ["\n\n✏️ Было:", "\n\n✏️ Was:"] {
        if let range = text.range(of: marker) {
            return String(text[text.startIndex ..< range.lowerBound])
        }
    }
    return text
}

/// The "Details" window: ids, author, dates, forward origin and views.
private func kimogramMessageDetails(message: EngineRawMessage, ru: Bool) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "dd.MM.yyyy HH:mm:ss"
    func date(_ timestamp: Int32) -> String {
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }
    var lines: [String] = []
    lines.append((ru ? "ID сообщения: " : "Message ID: ") + "\(message.id.id)")
    lines.append((ru ? "ID чата: " : "Chat ID: ") + "\(message.id.peerId.id._internalGetInt64Value())")
    if let author = message.author {
        let name = EnginePeer(author).compactDisplayTitle
        lines.append((ru ? "Автор: " : "Author: ") + name + " (ID \(author.id.id._internalGetInt64Value()))")
        if let username = EnginePeer(author).addressName, !username.isEmpty {
            lines.append("@" + username)
        }
    }
    lines.append((ru ? "Отправлено: " : "Sent: ") + date(message.timestamp))
    for attribute in message.attributes {
        if let attribute = attribute as? EditedMessageAttribute, !attribute.isHidden {
            lines.append((ru ? "Изменено: " : "Edited: ") + date(attribute.date))
        }
        if let attribute = attribute as? ViewCountMessageAttribute {
            lines.append((ru ? "Просмотры: " : "Views: ") + "\(attribute.count)")
        }
    }
    if let forwardInfo = message.forwardInfo {
        var origin = ""
        if let author = forwardInfo.author {
            origin = EnginePeer(author).compactDisplayTitle
        } else if let name = forwardInfo.authorSignature {
            origin = name
        }
        if let source = forwardInfo.source, source.id != forwardInfo.author?.id {
            origin += origin.isEmpty ? EnginePeer(source).compactDisplayTitle : " / " + EnginePeer(source).compactDisplayTitle
        }
        lines.append((ru ? "Переслано от: " : "Forwarded from: ") + (origin.isEmpty ? (ru ? "скрыто" : "hidden") : origin))
        lines.append((ru ? "Дата оригинала: " : "Original date: ") + date(forwardInfo.date))
    }
    if !message.media.isEmpty {
        var kinds: [String] = []
        for media in message.media {
            if media is TelegramMediaImage {
                kinds.append(ru ? "фото" : "photo")
            } else if let file = media as? TelegramMediaFile {
                if file.isVoice {
                    kinds.append(ru ? "голосовое" : "voice")
                } else if file.isVideo {
                    kinds.append(ru ? "видео" : "video")
                } else if file.isSticker || file.isAnimatedSticker {
                    kinds.append(ru ? "стикер" : "sticker")
                } else {
                    kinds.append(ru ? "файл" : "file")
                }
                if let size = file.size {
                    kinds[kinds.count - 1] += String(format: " %.1f MB", Double(size) / 1048576.0)
                }
            } else if media is TelegramMediaWebpage {
                kinds.append(ru ? "превью ссылки" : "link preview")
            }
        }
        if !kinds.isEmpty {
            lines.append((ru ? "Вложения: " : "Attachments: ") + kinds.joined(separator: ", "))
        }
    }
    return lines.joined(separator: "\n")
}
