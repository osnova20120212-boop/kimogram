import Foundation

/// Kimogram: removes tracking parameters (utm_*, fbclid, si, …) from the links in a message.
enum KimogramLinkCleaner {
    private static let trackingNames: Set<String> = [
        "fbclid", "gclid", "dclid", "gbraid", "wbraid", "yclid", "ysclid", "msclkid", "igshid", "igsh",
        "mc_cid", "mc_eid", "_hsenc", "_hsmi", "mkt_tok", "si", "feature", "ref_src", "ref_url", "spm",
        "vero_id", "oly_enc_id", "oly_anon_id", "rb_clickid", "s_cid", "__twitter_impression"
    ]

    private static func isTracking(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered.hasPrefix("utm_") || trackingNames.contains(lowered)
    }

    /// The text with every link cleaned, or nil when nothing changed.
    static func clean(_ text: String) -> String? {
        guard text.contains("?"), let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let nsText = text as NSString
        var result = text as NSString
        var changed = false
        let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        for match in matches.reversed() {
            let original = nsText.substring(with: match.range)
            guard var components = URLComponents(string: original), let items = components.queryItems, !items.isEmpty else {
                continue
            }
            // "si" and "feature" are only tracking on the video and music sites that add them.
            let host = components.host?.lowercased() ?? ""
            let filtered = items.filter { item in
                if !isTracking(item.name) {
                    return true
                }
                if item.name == "si" || item.name == "feature" {
                    return !(host.contains("youtu") || host.contains("spotify") || host.contains("music.yandex"))
                }
                return false
            }
            if filtered.count == items.count {
                continue
            }
            components.queryItems = filtered.isEmpty ? nil : filtered
            guard let cleaned = components.string, cleaned != original else {
                continue
            }
            result = result.replacingCharacters(in: match.range, with: cleaned) as NSString
            changed = true
        }
        return changed ? result as String : nil
    }
}
