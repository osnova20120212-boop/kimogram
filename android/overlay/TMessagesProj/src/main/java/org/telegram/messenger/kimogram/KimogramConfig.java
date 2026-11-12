package org.telegram.messenger.kimogram;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Build;

import org.telegram.messenger.ApplicationLoader;
import org.telegram.messenger.LocaleController;

/**
 * Kimogram: the mod's own switches, kept in their own preferences file so that the network
 * thread can read them at any time. Every switch starts off (Telegram's behaviour) unless
 * listed in {@link #defaultValue}.
 *
 * Store edition: when the app was installed from Google Play, switches that Telegram's API
 * terms forbid (ghost mode, hiding sponsored messages) are always off and not shown.
 */
public final class KimogramConfig {

    public static final String GHOST_READ = "ghost.readReceipts";
    public static final String GHOST_ONLINE = "ghost.online";
    public static final String GHOST_TYPING = "ghost.typing";
    public static final String GHOST_STORIES = "ghost.stories";
    public static final String HIDE_SPONSORED = "hideSponsored";
    public static final String HIDE_STORIES_BAR = "hideStoriesBar";
    public static final String CONFIRM_CALLS = "confirmCalls";
    public static final String HIDE_PREMIUM_ROWS = "hidePremiumRows";
    public static final String AUTO_PROXY = "autoProxy";

    private static SharedPreferences prefs;
    private static Boolean storeEdition;

    private KimogramConfig() {
    }

    private static SharedPreferences prefs() {
        if (prefs == null) {
            prefs = ApplicationLoader.applicationContext.getSharedPreferences("kimogram", Context.MODE_PRIVATE);
        }
        return prefs;
    }

    private static boolean defaultValue(String key) {
        return AUTO_PROXY.equals(key);
    }

    /** True for the switches Telegram's API terms do not allow in a store app. */
    public static boolean isRestricted(String key) {
        return key.startsWith("ghost.") || HIDE_SPONSORED.equals(key);
    }

    public static boolean get(String key) {
        if (isRestricted(key) && isStoreEdition()) {
            return false;
        }
        try {
            return prefs().getBoolean(key, defaultValue(key));
        } catch (Throwable e) {
            return defaultValue(key);
        }
    }

    public static void set(String key, boolean value) {
        prefs().edit().putBoolean(key, value).apply();
    }

    public static boolean toggle(String key) {
        boolean value = !get(key);
        set(key, value);
        return value;
    }

    /** Installed from Google Play. */
    public static boolean isStoreEdition() {
        if (storeEdition == null) {
            String installer = null;
            try {
                Context context = ApplicationLoader.applicationContext;
                if (Build.VERSION.SDK_INT >= 30) {
                    installer = context.getPackageManager().getInstallSourceInfo(context.getPackageName()).getInstallingPackageName();
                } else {
                    installer = context.getPackageManager().getInstallerPackageName(context.getPackageName());
                }
            } catch (Throwable ignore) {
            }
            storeEdition = "com.android.vending".equals(installer);
        }
        return storeEdition;
    }

    public static boolean ghostAny() {
        return get(GHOST_READ) || get(GHOST_ONLINE) || get(GHOST_TYPING) || get(GHOST_STORIES);
    }

    public static boolean hideStoriesBar() {
        return get(HIDE_STORIES_BAR);
    }

    public static boolean hideSponsored() {
        return get(HIDE_SPONSORED);
    }

    public static boolean hidePremiumRows() {
        return get(HIDE_PREMIUM_ROWS);
    }

    /** Russian text when the app speaks Russian, English otherwise. */
    public static String t(String ru, String en) {
        try {
            String lang = LocaleController.getInstance().getCurrentLocale().getLanguage();
            return "ru".equals(lang) || "uk".equals(lang) || "be".equals(lang) ? ru : en;
        } catch (Throwable e) {
            return en;
        }
    }
}
