import Foundation
import SwiftSignalKit
import Postbox

/// Kimogram: the mod's own switches.
///
/// Stored in the app's standard defaults so that the network layer can read them synchronously
/// on any queue. Almost every switch defaults to off (see `defaults`).
public final class KimogramSettings {
    public enum Key: String, CaseIterable {
        case ghostReadReceipts = "kimogram.ghost.readReceipts"
        case ghostOnline = "kimogram.ghost.online"
        case ghostTyping = "kimogram.ghost.typing"
        case ghostStories = "kimogram.ghost.stories"
        case hideSponsored = "kimogram.hideSponsored"
        case showPeerId = "kimogram.showPeerId"
        case hideStoriesBar = "kimogram.hideStoriesBar"
        case confirmCalls = "kimogram.confirmCalls"
        case fastAnimations = "kimogram.fastAnimations"
        case saveDeletedMessages = "kimogram.saveDeletedMessages"
        case saveEditHistory = "kimogram.saveEditHistory"
        case hidePhoneNumber = "kimogram.hidePhoneNumber"
        case hidePremiumRows = "kimogram.hidePremiumRows"
        case timestampSeconds = "kimogram.timestampSeconds"
        case fastDownloads = "kimogram.fastDownloads"
        case ghostReadOnReply = "kimogram.ghost.readOnReply"
        case ghostVoiceListened = "kimogram.ghost.voiceListened"
        case saveProtected = "kimogram.saveProtected"
        case extendedMessageMenu = "kimogram.extendedMessageMenu"
        case confirmStickers = "kimogram.confirmStickers"
        case confirmVoice = "kimogram.confirmVoice"
        case disableSwipeReply = "kimogram.disableSwipeReply"
        case hideContactsTab = "kimogram.hideContactsTab"
        case hidePremiumBadges = "kimogram.hidePremiumBadges"
        case hideSimilarChannels = "kimogram.hideSimilarChannels"
        case hideReactions = "kimogram.hideReactions"
        case openLinksDirectly = "kimogram.openLinksDirectly"
        case keepSelfDestructing = "kimogram.keepSelfDestructing"
        case hideFolderBadges = "kimogram.hideFolderBadges"
        case hideShareButton = "kimogram.hideShareButton"
    }

    /// Switches that are on until the user turns them off. Everything else starts off,
    /// which is exactly the behaviour of Telegram.
    private static let defaults: UserDefaults = {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Key.extendedMessageMenu.rawValue: true
        ])
        return defaults
    }()
    private static let updatesPipe = ValuePipe<Void>()

    public static func get(_ key: Key) -> Bool {
        return defaults.bool(forKey: key.rawValue)
    }

    public static func set(_ key: Key, _ value: Bool) {
        defaults.set(value, forKey: key.rawValue)
        updatesPipe.putNext(Void())
    }

    /// Emits the current value and then every change.
    public static func signal(_ key: Key) -> Signal<Bool, NoError> {
        return Signal<Bool, NoError>.single(get(key))
        |> then(updatesPipe.signal() |> map { _ -> Bool in
            return get(key)
        })
        |> distinctUntilChanged
    }

    /// Emits whenever any switch changes, starting immediately.
    public static func changes() -> Signal<Void, NoError> {
        return Signal<Void, NoError>.single(Void()) |> then(updatesPipe.signal())
    }

    public static var ghostModeEnabled: Bool {
        return get(.ghostReadReceipts) && get(.ghostOnline) && get(.ghostTyping) && get(.ghostStories) && get(.ghostVoiceListened)
    }

    public static func setGhostMode(_ value: Bool) {
        defaults.set(value, forKey: Key.ghostReadReceipts.rawValue)
        defaults.set(value, forKey: Key.ghostOnline.rawValue)
        defaults.set(value, forKey: Key.ghostTyping.rawValue)
        defaults.set(value, forKey: Key.ghostStories.rawValue)
        defaults.set(value, forKey: Key.ghostVoiceListened.rawValue)
        updatesPipe.putNext(Void())
    }

    /// What a double tap on a message does.
    public enum DoubleTapAction: Int, CaseIterable {
        case reaction = 0
        case reply = 1
        case menu = 2
        case nothing = 3
    }

    private static let doubleTapActionKey = "kimogram.doubleTapAction"

    public static var doubleTapAction: DoubleTapAction {
        get {
            return DoubleTapAction(rawValue: defaults.integer(forKey: doubleTapActionKey)) ?? .reaction
        }
        set {
            defaults.set(newValue.rawValue, forKey: doubleTapActionKey)
            updatesPipe.putNext(Void())
        }
    }

    /// Sticker size in chats.
    public enum StickerSize: Int, CaseIterable {
        case normal = 0
        case small = 1
        case medium = 2
        case large = 3

        public var scale: Double {
            switch self {
            case .normal:
                return 1.0
            case .small:
                return 0.7
            case .medium:
                return 0.85
            case .large:
                return 1.15
            }
        }
    }

    private static let stickerSizeKey = "kimogram.stickerSize"

    public static var stickerSize: StickerSize {
        get {
            return StickerSize(rawValue: defaults.integer(forKey: stickerSizeKey)) ?? .normal
        }
        set {
            defaults.set(newValue.rawValue, forKey: stickerSizeKey)
            updatesPipe.putNext(Void())
        }
    }

    // MARK: Locked chats

    private static let lockedChatsKey = "kimogram.lockedChats"

    /// Chats that open only after Face ID, Touch ID or the device passcode.
    public static func isChatLocked(_ peerId: PeerId) -> Bool {
        let ids = defaults.array(forKey: lockedChatsKey) as? [String] ?? []
        return ids.contains("\(peerId.toInt64())")
    }

    public static func setChatLocked(_ peerId: PeerId, _ locked: Bool) {
        var ids = defaults.array(forKey: lockedChatsKey) as? [String] ?? []
        let id = "\(peerId.toInt64())"
        ids.removeAll(where: { $0 == id })
        if locked {
            ids.append(id)
        }
        defaults.set(ids, forKey: lockedChatsKey)
        updatesPipe.putNext(Void())
    }

    public static var lockedChatCount: Int {
        return (defaults.array(forKey: lockedChatsKey) as? [String] ?? []).count
    }

    // MARK: Ghost mode exceptions

    private static let ghostExceptionsKey = "kimogram.ghost.exceptions"

    /// Chats where ghost mode does not apply: reading and typing are shown there as usual.
    public static func isGhostException(_ peerId: PeerId) -> Bool {
        let ids = defaults.array(forKey: ghostExceptionsKey) as? [String] ?? []
        return ids.contains("\(peerId.toInt64())")
    }

    public static func setGhostException(_ peerId: PeerId, _ value: Bool) {
        var ids = defaults.array(forKey: ghostExceptionsKey) as? [String] ?? []
        let id = "\(peerId.toInt64())"
        ids.removeAll(where: { $0 == id })
        if value {
            ids.append(id)
        }
        defaults.set(ids, forKey: ghostExceptionsKey)
        updatesPipe.putNext(Void())
    }

    public static var ghostExceptionPeerIds: [PeerId] {
        let ids = defaults.array(forKey: ghostExceptionsKey) as? [String] ?? []
        return ids.compactMap { Int64($0) }.map { PeerId($0) }
    }

    /// Whether "read" receipts are hidden in this chat.
    public static func hidesReadReceipts(in peerId: PeerId) -> Bool {
        return get(.ghostReadReceipts) && !isGhostException(peerId)
    }

    /// Whether "typing…" is hidden in this chat.
    public static func hidesTyping(in peerId: PeerId) -> Bool {
        return get(.ghostTyping) && !isGhostException(peerId)
    }

    // MARK: Export and import

    /// All Kimogram settings as text, to keep or move to another device.
    public static func exportedText() -> String {
        var dict: [String: Any] = [:]
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix("kimogram.") {
            if value is NSNumber || value is [String] {
                dict[key] = value
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return "KIMOGRAM:" + text
    }

    /// Applies text made by `exportedText()`. Returns false when the text is not Kimogram settings.
    @discardableResult
    public static func importText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("KIMOGRAM:") else {
            return false
        }
        guard let data = String(trimmed.dropFirst("KIMOGRAM:".count)).data(using: .utf8), let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return false
        }
        var applied = false
        for (key, value) in dict where key.hasPrefix("kimogram.") {
            if let list = value as? [String] {
                defaults.set(list, forKey: key)
                applied = true
            } else if let number = value as? NSNumber {
                defaults.set(number, forKey: key)
                applied = true
            }
        }
        updatesPipe.putNext(Void())
        return applied
    }
}
