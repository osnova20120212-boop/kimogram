import Foundation
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import AccountContext

/// Kimogram's own colours: the violet of the crystal logo.
///
/// Each built-in theme gets a "Kimogram" colour preset (listed first in Appearance), and a
/// fresh install starts with it: violet accent, violet message bubbles and a softly animated
/// violet pattern wallpaper. A colour the user already chose is never replaced.
let kimogramAccentIndex: Int32 = 110

let kimogramDayClassicPreset = PresentationThemeAccentColor(index: kimogramAccentIndex, baseColor: .preset, accentColor: 0xFF7B5CFF, bubbleColors: [0xFFF1EAFF, 0xFFE2D6FF], wallpaper: defaultBuiltinWallpaper(data: .variant14, colors: [0xc9b8ff, 0x8f7bf0, 0xe3d6ff, 0xa58cff], intensity: 50, rotation: nil))

let kimogramDayPreset = PresentationThemeAccentColor(index: kimogramAccentIndex, baseColor: .preset, accentColor: 0xFF7B5CFF, bubbleColors: [0xFF8A5CFF, 0xFF5B7CFF], wallpaper: nil)

let kimogramNightPreset = PresentationThemeAccentColor(index: kimogramAccentIndex, baseColor: .preset, accentColor: 0xFF9C84FF, bubbleColors: [0xFF8A5CFF, 0xFF5A4FE0], wallpaper: defaultBuiltinWallpaper(data: .variant6, colors: [0x6a3de8, 0x24164f, 0x8a5cff, 0x3a2a8a], intensity: -35, rotation: nil))

private let kimogramThemeAppliedKey = "kimogram.theme.applied.v1"

/// Gives a fresh install the Kimogram colours, once.
public func kimogramApplyThemeIfNeeded(sharedContext: SharedAccountContext) {
    if UserDefaults.standard.bool(forKey: kimogramThemeAppliedKey) {
        return
    }
    UserDefaults.standard.set(true, forKey: kimogramThemeAppliedKey)

    let _ = updatePresentationThemeSettingsInteractively(accountManager: sharedContext.accountManager, { current in
        var updated = current
        let pairs: [(PresentationThemeReference, PresentationThemeAccentColor)] = [
            (.builtin(.dayClassic), kimogramDayClassicPreset),
            (.builtin(.day), kimogramDayPreset),
            (.builtin(.night), kimogramNightPreset)
        ]
        for (reference, preset) in pairs {
            if updated.themeSpecificAccentColors[reference.index] != nil {
                continue
            }
            updated.themeSpecificAccentColors[reference.index] = preset
            if let wallpaper = preset.wallpaper {
                let index = coloredThemeIndex(reference: reference, accentColor: preset)
                if updated.themeSpecificChatWallpapers[index] == nil {
                    updated.themeSpecificChatWallpapers[index] = wallpaper
                }
            }
        }
        return updated
    }).start()
}
