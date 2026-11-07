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
            return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: text, attributes: currentMessage.attributes, media: currentMessage.media))
        })
    }
    return remaining
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
