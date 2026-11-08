import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi

private var kimogramIsRussian: Bool {
    let language = Locale.preferredLanguages.first ?? ""
    return language.hasPrefix("ru") || language.hasPrefix("uk") || language.hasPrefix("be")
}

private var kimogramDeletedMarker: String {
    return kimogramIsRussian ? "🗑 Удалено" : "🗑 Deleted"
}

private var kimogramEditedMarker: String {
    return kimogramIsRussian ? "✏️ Было:" : "✏️ Was:"
}

/// Kimogram: styles the mod's own notes in a message's text. The earlier version of an edited
/// message becomes a collapsed quote (tap to expand) and the "deleted" note is set in italics,
/// so both read as notes rather than as part of what the person wrote.
func kimogramDecoratedAttributes(text: String, attributes: [MessageAttribute]) -> [MessageAttribute] {
    let nsText = text as NSString
    let length = nsText.length

    var deletedStart = length
    let deletedRange = nsText.range(of: kimogramDeletedMarker, options: .backwards)
    if deletedRange.location != NSNotFound && deletedRange.location + deletedRange.length == length {
        deletedStart = deletedRange.location
    }

    var added: [MessageTextEntity] = []
    var historyStart = length
    let editRange = nsText.range(of: "\n\n" + kimogramEditedMarker)
    if editRange.location != NSNotFound {
        historyStart = editRange.location + 2
        var historyEnd = deletedStart < length ? deletedStart : length
        // Leave out the blank line before the deleted note.
        while historyEnd > historyStart, nsText.character(at: historyEnd - 1) == 0x0A {
            historyEnd -= 1
        }
        if historyEnd > historyStart {
            added.append(MessageTextEntity(range: historyStart ..< historyEnd, type: .BlockQuote(isCollapsed: true)))
        }
    }
    if deletedStart < length {
        added.append(MessageTextEntity(range: deletedStart ..< length, type: .Italic))
    }
    if added.isEmpty {
        return attributes
    }

    var result = attributes
    var existing: [MessageTextEntity] = []
    if let index = result.firstIndex(where: { $0 is TextEntitiesMessageAttribute }), let attribute = result[index] as? TextEntitiesMessageAttribute {
        existing = attribute.entities
        result.remove(at: index)
    }
    // The server's entities describe only the current text; anything from the notes onwards is ours.
    let notesStart = min(historyStart, deletedStart)
    existing = existing.filter { $0.range.upperBound <= notesStart }
    result.append(TextEntitiesMessageAttribute(entities: existing + added))
    return result
}

/// Kimogram "save deleted messages": instead of deleting cloud messages that the server says
/// were deleted, mark them and keep them. Returns the ids that must still be deleted (local,
/// scheduled and secret-chat messages, and ones that are not stored).
func kimogramKeepDeletedMessages(transaction: Transaction, ids: [MessageId]) -> [MessageId] {
    var remaining: [MessageId] = []
    let marker = kimogramDeletedMarker
    for id in ids {
        guard id.namespace == Namespaces.Message.Cloud, id.peerId.namespace != Namespaces.Peer.SecretChat, let message = transaction.getMessage(id) else {
            remaining.append(id)
            continue
        }
        if message.text.hasSuffix(marker) {
            continue
        }
        transaction.updateMessage(id, update: { currentMessage in
            var storeForwardInfo: StoreMessageForwardInfo?
            if let forwardInfo = currentMessage.forwardInfo {
                storeForwardInfo = StoreMessageForwardInfo(authorId: forwardInfo.author?.id, sourceId: forwardInfo.source?.id, sourceMessageId: forwardInfo.sourceMessageId, date: forwardInfo.date, authorSignature: forwardInfo.authorSignature, psaType: forwardInfo.psaType, flags: forwardInfo.flags)
            }
            let text = currentMessage.text.isEmpty ? marker : currentMessage.text + "\n\n" + marker
            let attributes = kimogramDecoratedAttributes(text: text, attributes: currentMessage.attributes)
            return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: text, attributes: attributes, media: currentMessage.media))
        })
        KimogramSettings.incrementStat(.deletedKept)
        KimogramDeletedLog.append(KimogramDeletedLog.Entry(
            peerId: id.peerId.toInt64(),
            messageId: id.id,
            timestamp: message.timestamp,
            deletedAt: Int32(Date().timeIntervalSince1970),
            chatTitle: kimogramPeerTitle(message.peers[id.peerId]),
            author: kimogramPeerTitle(message.author),
            text: message.text.isEmpty ? (message.media.isEmpty ? "" : (kimogramIsRussian ? "Вложение" : "Attachment")) : message.text
        ))
    }
    return remaining
}

private func kimogramPeerTitle(_ peer: Peer?) -> String {
    if let user = peer as? TelegramUser {
        let name = [user.firstName ?? "", user.lastName ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? (user.addressName ?? "") : name
    } else if let group = peer as? TelegramGroup {
        return group.title
    } else if let channel = peer as? TelegramChannel {
        return channel.title
    }
    return ""
}

/// Kimogram: a list of the messages kept after their deletion, for the "Deleted Messages" screen.
/// Lives in the standard defaults, newest last, at most `limit` entries.
public enum KimogramDeletedLog {
    public struct Entry: Codable, Equatable {
        public var peerId: Int64
        public var messageId: Int32
        public var timestamp: Int32
        public var deletedAt: Int32
        public var chatTitle: String
        public var author: String
        public var text: String
    }

    private static let key = "kimogram.deletedLog"
    private static let limit = 1000

    public static func all() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key), let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        return entries
    }

    static func append(_ entry: Entry) {
        var entries = all()
        entries.removeAll(where: { $0.peerId == entry.peerId && $0.messageId == entry.messageId })
        entries.append(entry)
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    public static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        KimogramSettings.notifyChanged()
    }
}

/// Kimogram "save edit history": the text an edited incoming message should be stored with, or
/// nil to store the server's text as it is.
func kimogramTextKeepingEditHistory(previousText: String, updatedText: String) -> String? {
    let marker = "\n\n" + kimogramEditedMarker + " "
    let previousOriginal: String
    if let range = previousText.range(of: marker) {
        previousOriginal = String(previousText[previousText.startIndex ..< range.lowerBound])
    } else {
        previousOriginal = previousText
    }
    if previousOriginal == updatedText {
        // Not a text edit (reactions, a link preview): keep the history already shown.
        return previousText == updatedText ? nil : previousText
    }
    if previousOriginal.isEmpty {
        return nil
    }
    KimogramSettings.incrementStat(.editsKept)
    return updatedText + marker + previousText
}

/// Kimogram ghost mode: answering a chat is the moment to let it know you read it. Pushes the
/// local read position of that chat to the server once, as a regular client would.
func kimogramMarkReadOnReply(account: Account, peerId: PeerId) {
    if peerId.namespace == Namespaces.Peer.SecretChat {
        return
    }
    let network = account.network
    let _ = (account.postbox.transaction { transaction -> (Peer, MessageId.Id)? in
        guard let peer = transaction.getPeer(peerId), let states = transaction.getPeerReadStates(peerId) else {
            return nil
        }
        for (namespace, state) in states where namespace == Namespaces.Message.Cloud {
            if case let .idBased(maxIncomingReadId, _, _, _, _) = state, maxIncomingReadId > 0 {
                return (peer, maxIncomingReadId)
            }
        }
        return nil
    }
    |> mapToSignal { value -> Signal<Never, NoError> in
        guard let value else {
            return .complete()
        }
        let peer = value.0
        let maxId = value.1
        if let inputChannel = apiInputChannel(peer) {
            return network.request(Api.functions.channels.readHistory(channel: inputChannel, maxId: maxId))
            |> `catch` { _ -> Signal<Api.Bool, NoError> in
                return .complete()
            }
            |> ignoreValues
        } else if let inputPeer = apiInputPeer(peer) {
            return network.request(Api.functions.messages.readHistory(peer: inputPeer, maxId: maxId))
            |> `catch` { _ -> Signal<Api.messages.AffectedMessages, NoError> in
                return .complete()
            }
            |> ignoreValues
        } else {
            return .complete()
        }
    }).start()
}

/// Kimogram ghost mode: "Mark Read Up to Here". Tells the server (and so the sender) that the
/// messages up to `messageId` were read, while ghost mode keeps hiding everything else.
public func kimogramSendReadReceipt(account: Account, messageId: MessageId) {
    let peerId = messageId.peerId
    if peerId.namespace == Namespaces.Peer.SecretChat || messageId.namespace != Namespaces.Message.Cloud {
        return
    }
    let network = account.network
    let _ = (account.postbox.transaction { transaction -> Peer? in
        return transaction.getPeer(peerId)
    }
    |> mapToSignal { peer -> Signal<Never, NoError> in
        guard let peer else {
            return .complete()
        }
        if let inputChannel = apiInputChannel(peer) {
            return network.request(Api.functions.channels.readHistory(channel: inputChannel, maxId: messageId.id))
            |> `catch` { _ -> Signal<Api.Bool, NoError> in
                return .complete()
            }
            |> ignoreValues
        } else if let inputPeer = apiInputPeer(peer) {
            return network.request(Api.functions.messages.readHistory(peer: inputPeer, maxId: messageId.id))
            |> `catch` { _ -> Signal<Api.messages.AffectedMessages, NoError> in
                return .complete()
            }
            |> ignoreValues
        } else {
            return .complete()
        }
    }).start()
}
