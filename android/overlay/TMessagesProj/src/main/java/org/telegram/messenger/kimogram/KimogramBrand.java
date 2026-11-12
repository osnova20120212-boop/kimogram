package org.telegram.messenger.kimogram;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Kimogram: shows "Kimogram" instead of "Telegram" in every string the app reads through
 * LocaleController (built-in and cloud language packs).
 *
 * Left as they are, because they name Telegram's own services or addresses rather than the app:
 * Telegram Premium / Stars / Business / Gateway / Passport, "the Telegram app" (login codes go
 * to the official app on another device), and addresses (telegram.org, @Telegram, /telegram).
 */
public final class KimogramBrand {

    private static final Pattern WORD = Pattern.compile(
        "(?<![@/\\w.])Telegram(?![\\w]|\\.(?:org|me|com)| (?:Premium|Stars|Business|Gateway|Passport|app|API)\\b)"
    );
    private static final Pattern APP_RU = Pattern.compile("(?i)(приложени[еяию]\\s+)Kimogram");

    private KimogramBrand() {
    }

    public static String apply(String value) {
        if (value == null || value.indexOf("Telegram") < 0) {
            return value;
        }
        Matcher matcher = WORD.matcher(value);
        if (!matcher.find()) {
            return value;
        }
        String result = matcher.replaceAll("Kimogram");
        // "в приложении Telegram" names the official app (where login codes arrive), keep it.
        return APP_RU.matcher(result).replaceAll("$1Telegram");
    }
}
