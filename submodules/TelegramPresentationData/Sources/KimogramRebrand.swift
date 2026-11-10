import Foundation
import TelegramCore

/// Kimogram: every on-screen string says "Kimogram" where Telegram's said "Telegram".
///
/// Applied once to each localization dictionary as it is loaded (bundled and downloaded), so
/// it covers every language. Only the capitalized word is replaced: lower-case "telegram" is
/// part of addresses such as telegram.org and t.me links and must stay as it is.
///
/// The App Store edition keeps the names of what Telegram itself sells and runs (Premium,
/// Stars, Business): calling them "Kimogram Premium" would read as if Kimogram sold them.
public func kimogramRebrandStrings(_ dict: [String: String]) -> [String: String] {
    let kept = KimogramSettings.storeEdition ? kimogramStoreKeptNames : []
    var result = dict
    for (key, value) in dict {
        if value.contains("Telegram") || value.contains("TELEGRAM") {
            var text = value
            for (index, name) in kept.enumerated() {
                text = text.replacingOccurrences(of: name, with: "\u{E000}\(index)\u{E001}")
            }
            text = text
                .replacingOccurrences(of: "Telegram", with: "Kimogram")
                .replacingOccurrences(of: "TELEGRAM", with: "KIMOGRAM")
            for (index, name) in kept.enumerated() {
                text = text.replacingOccurrences(of: "\u{E000}\(index)\u{E001}", with: name)
            }
            result[key] = text
        }
    }
    return result
}

private let kimogramStoreKeptNames: [String] = [
    "Telegram Premium", "TELEGRAM PREMIUM",
    "Telegram Stars", "TELEGRAM STARS",
    "Telegram Business", "TELEGRAM BUSINESS"
]
