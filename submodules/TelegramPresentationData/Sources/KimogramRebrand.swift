import Foundation

/// Kimogram: every on-screen string says "Kimogram" where Telegram's said "Telegram".
///
/// Applied once to each localization dictionary as it is loaded (bundled and downloaded), so
/// it covers every language. Only the capitalized word is replaced: lower-case "telegram" is
/// part of addresses such as telegram.org and t.me links and must stay as it is.
public func kimogramRebrandStrings(_ dict: [String: String]) -> [String: String] {
    var result = dict
    for (key, value) in dict {
        if value.contains("Telegram") || value.contains("TELEGRAM") {
            result[key] = value
                .replacingOccurrences(of: "Telegram", with: "Kimogram")
                .replacingOccurrences(of: "TELEGRAM", with: "KIMOGRAM")
        }
    }
    return result
}
