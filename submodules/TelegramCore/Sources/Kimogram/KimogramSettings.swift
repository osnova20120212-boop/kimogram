import Foundation
import SwiftSignalKit

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
}
