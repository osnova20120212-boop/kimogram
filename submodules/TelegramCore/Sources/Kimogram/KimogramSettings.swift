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
        case hideRecordingActivity = "kimogram.ghost.recordingActivity"
        case noScreenshotNotice = "kimogram.ghost.noScreenshotNotice"
        case noViewIncrement = "kimogram.ghost.noViewIncrement"
        case blurInAppSwitcher = "kimogram.blurInAppSwitcher"
        case hideHelpSection = "kimogram.hideHelpSection"
        case noMusicCard = "kimogram.noMusicCard"
        case hideChatsTabBadge = "kimogram.hideChatsTabBadge"
        case hideAppIconBadge = "kimogram.hideAppIconBadge"
        case hideEditButton = "kimogram.hideEditButton"
        case noLinkPreviews = "kimogram.noLinkPreviews"
        case hideBotButtons = "kimogram.hideBotButtons"
        case hideStickerButton = "kimogram.hideStickerButton"
        case hideGiftButton = "kimogram.hideGiftButton"
        case hidePaidReactions = "kimogram.hidePaidReactions"
        case charCounter = "kimogram.charCounter"
        case confirmSend = "kimogram.confirmSend"
        case noChatPreview = "kimogram.noChatPreview"
        case quickDelete = "kimogram.quickDelete"
        case forwardWithoutAuthor = "kimogram.forwardWithoutAuthor"
        case noSuspiciousLinkWarning = "kimogram.noSuspiciousLinkWarning"
        case titleAccountName = "kimogram.titleAccountName"
        case noChatListSeparators = "kimogram.noChatListSeparators"
        case hideStoryCamera = "kimogram.hideStoryCamera"
        case silentByDefault = "kimogram.silentByDefault"
        case pinSilently = "kimogram.pinSilently"
        case stripTrackingParams = "kimogram.stripTrackingParams"
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

    /// The App Store edition. Telegram's API terms (core.telegram.org/api/terms, 1.4 and 3.3)
    /// forbid ghost mode, tampering with read, online and typing statuses, keeping
    /// self-destructing content and hiding official sponsored messages; Apple reviews against
    /// them too. In this edition those switches always read off and their rows are hidden.
    /// Set from `BuildConfig.isAppStoreBuild` at launch, before any network work starts.
    public static var storeEdition: Bool = false

    public static let storeForbiddenKeys: Set<Key> = [
        .ghostReadReceipts, .ghostOnline, .ghostTyping, .ghostStories, .ghostReadOnReply,
        .ghostVoiceListened, .hideRecordingActivity, .noScreenshotNotice, .noViewIncrement,
        .saveDeletedMessages, .keepSelfDestructing, .saveProtected, .hideSponsored
    ]

    /// Always on in the App Store edition: Apple requires digital goods to be sold through its
    /// own in-app purchases (guideline 3.1.1), and this build has none, so the Premium, gift and
    /// paid-reaction entry points stay hidden.
    public static let storeForcedKeys: Set<Key> = [
        .hidePremiumRows, .hideGiftButton, .hidePaidReactions
    ]

    public static func isAvailable(_ key: Key) -> Bool {
        return !(storeEdition && (storeForbiddenKeys.contains(key) || storeForcedKeys.contains(key)))
    }

    public static func get(_ key: Key) -> Bool {
        if storeEdition {
            if storeForbiddenKeys.contains(key) {
                return false
            }
            if storeForcedKeys.contains(key) {
                return true
            }
        }
        if defaults.bool(forKey: key.rawValue) {
            return true
        }
        // Ghost mode on a schedule: the basic ghost switches are on inside the chosen hours.
        switch key {
        case .ghostReadReceipts, .ghostOnline, .ghostTyping, .ghostStories, .ghostVoiceListened:
            return ghostScheduleActiveNow
        default:
            return false
        }
    }

    /// Counters shown on the Kimogram Settings page.
    public enum Stat: String {
        case deletedKept = "kimogram.stats.deletedKept"
        case editsKept = "kimogram.stats.editsKept"
    }

    public static func incrementStat(_ stat: Stat) {
        defaults.set(defaults.integer(forKey: stat.rawValue) + 1, forKey: stat.rawValue)
    }

    public static func statValue(_ stat: Stat) -> Int {
        return defaults.integer(forKey: stat.rawValue)
    }

    /// The chat list's own title, when set (nil means "Kimogram").
    public static var customChatListTitle: String? {
        get {
            let value = defaults.string(forKey: "kimogram.customTitle")?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (value?.isEmpty ?? true) ? nil : value
        }
        set {
            defaults.set(newValue, forKey: "kimogram.customTitle")
            updatesPipe.putNext(Void())
        }
    }

    /// Ghost-mode schedules: start and end hour. Index 0 means no schedule.
    public static let ghostSchedules: [(from: Int, to: Int)] = [(0, 0), (23, 8), (22, 7), (0, 9), (9, 18)]
    private static let ghostScheduleKey = "kimogram.ghost.schedule"

    public static var ghostSchedule: Int {
        get {
            let value = defaults.integer(forKey: ghostScheduleKey)
            return value >= 0 && value < ghostSchedules.count ? value : 0
        }
        set {
            defaults.set(newValue, forKey: ghostScheduleKey)
            updatesPipe.putNext(Void())
        }
    }

    public static var ghostScheduleActiveNow: Bool {
        if storeEdition {
            return false
        }
        let index = ghostSchedule
        if index == 0 {
            return false
        }
        let (from, to) = ghostSchedules[index]
        let hour = Calendar.current.component(.hour, from: Date())
        if from < to {
            return hour >= from && hour < to
        } else {
            return hour >= from || hour < to
        }
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
    /// Tells open settings pages to rebuild.
    public static func notifyChanged() {
        updatesPipe.putNext(Void())
    }

    public static func changes() -> Signal<Void, NoError> {
        return Signal<Void, NoError>.single(Void()) |> then(updatesPipe.signal())
    }

    public static var ghostModeEnabled: Bool {
        return get(.ghostReadReceipts) && get(.ghostOnline) && get(.ghostTyping) && get(.ghostStories) && get(.ghostVoiceListened)
    }

    public static func setGhostMode(_ value: Bool) {
        if storeEdition {
            return
        }
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

    private static let bubbleWidthKey = "kimogram.bubbleWidth"

    /// Message bubble width: 0 is Telegram's, 1 narrower, 2 wider.
    public static var bubbleWidth: Int {
        get {
            return max(0, min(2, defaults.integer(forKey: bubbleWidthKey)))
        }
        set {
            defaults.set(newValue, forKey: bubbleWidthKey)
            updatesPipe.putNext(Void())
        }
    }

    private static let roundVideoSizeKey = "kimogram.roundVideoSize"

    /// Round video message size: 0 is Telegram's, 1 large.
    public static var roundVideoSize: Int {
        get {
            return max(0, min(1, defaults.integer(forKey: roundVideoSizeKey)))
        }
        set {
            defaults.set(newValue, forKey: roundVideoSizeKey)
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

    private static let hiddenChatsKey = "kimogram.hiddenChats"

    /// Chats left out of the chat list. They are found through search and are always locked.
    public static func isChatHidden(_ peerId: PeerId) -> Bool {
        return hiddenChatIds.contains("\(peerId.toInt64())")
    }

    public static var hiddenChatIds: [String] {
        return defaults.array(forKey: hiddenChatsKey) as? [String] ?? []
    }

    public static func setChatHidden(_ peerId: PeerId, _ hidden: Bool) {
        var ids = hiddenChatIds
        let id = "\(peerId.toInt64())"
        ids.removeAll(where: { $0 == id })
        if hidden {
            ids.append(id)
        }
        defaults.set(ids, forKey: hiddenChatsKey)
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

    /// Turns every Kimogram setting back to its default. Locked chats stay locked: unlocking
    /// them is a separate, deliberate step.
    public static func resetAll() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("kimogram.") {
            if key == lockedChatsKey || key == hiddenChatsKey || key.hasPrefix("kimogram.music.") {
                continue
            }
            defaults.removeObject(forKey: key)
        }
        updatesPipe.putNext(Void())
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
