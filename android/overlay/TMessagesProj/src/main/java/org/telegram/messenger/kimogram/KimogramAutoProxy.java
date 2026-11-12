package org.telegram.messenger.kimogram;

import android.content.SharedPreferences;
import android.net.Uri;
import android.os.SystemClock;
import android.text.TextUtils;

import org.telegram.messenger.AndroidUtilities;
import org.telegram.messenger.FileLog;
import org.telegram.messenger.MessagesController;
import org.telegram.messenger.NotificationCenter;
import org.telegram.messenger.SharedConfig;
import org.telegram.messenger.UserConfig;
import org.telegram.messenger.Utilities;
import org.telegram.tgnet.ConnectionsManager;
import org.telegram.utils.proxy.ProxySettings;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.Set;

/**
 * Kimogram auto-proxy (same behaviour as on iPhone).
 *
 * While enabled it watches the connection. When the app cannot reach Telegram for a while, it
 * downloads Kimogram's checked list of free MTProto proxies (public lists as a fallback), pings a
 * batch through Telegram's own proxy check and switches to the fastest one. If that proxy stops
 * working, the same happens again.
 *
 * It only replaces a proxy it added itself: a proxy the user set up by hand is never touched.
 * Turning the feature off removes every proxy it added. Everything runs on the main thread.
 */
public final class KimogramAutoProxy {

    private static final String[] LISTS = {
        "https://raw.githubusercontent.com/osnova20120212-boop/kimogram/proxies/list.txt",
        "https://cdn.jsdelivr.net/gh/osnova20120212-boop/kimogram@proxies/list.txt",
        "https://raw.githubusercontent.com/Argh94/Proxy-List/main/MTProto.txt",
        "https://raw.githubusercontent.com/SoliSpirit/mtproto/master/all_proxies.txt",
    };
    private static final long BAD_CONNECTION_MS = 12_000;
    private static final long PING_TIMEOUT_MS = 8_000;
    private static final long RETRY_AFTER_FAILURE_MS = 60_000;
    private static final int BATCH = 30;
    private static final String ADDED_KEY = "autoProxy.added";

    private static KimogramAutoProxy instance;

    private boolean started;
    private long badSince;
    private boolean switching;
    private long lastFailure;
    private int probeToken;
    private String status = "";

    public static KimogramAutoProxy getInstance() {
        if (instance == null) {
            instance = new KimogramAutoProxy();
        }
        return instance;
    }

    public void start() {
        if (started) {
            return;
        }
        started = true;
        AndroidUtilities.runOnUIThread(this::tick, 3000);
    }

    public boolean isEnabled() {
        return KimogramConfig.get(KimogramConfig.AUTO_PROXY);
    }

    public void setEnabled(boolean enabled) {
        KimogramConfig.set(KimogramConfig.AUTO_PROXY, enabled);
        badSince = 0;
        if (!enabled) {
            probeToken++;
            switching = false;
            removeAdded(null);
            status = "";
        }
        start();
    }

    /** One line about what auto mode is doing, for the settings page. */
    public String getStatus() {
        if (!isEnabled()) {
            return KimogramConfig.t("Выключено", "Off");
        }
        if (switching) {
            return KimogramConfig.t("Ищу быстрый прокси…", "Looking for a fast proxy…");
        }
        if (SharedConfig.isProxyEnabled() && SharedConfig.currentProxy != null && isAdded(SharedConfig.currentProxy.settings)) {
            return KimogramConfig.t("Подключено через ", "Connected via ") + SharedConfig.currentProxy.settings.getAddress();
        }
        if (!TextUtils.isEmpty(status)) {
            return status;
        }
        return KimogramConfig.t("Включится, если Telegram недоступен", "Turns on when Telegram is unreachable");
    }

    private void tick() {
        AndroidUtilities.runOnUIThread(this::tick, 3000);
        if (!isEnabled() || switching) {
            return;
        }
        final int state = ConnectionsManager.getInstance(UserConfig.selectedAccount).getConnectionState();
        if (state != ConnectionsManager.ConnectionStateConnecting && state != ConnectionsManager.ConnectionStateConnectingToProxy) {
            badSince = 0;
            return;
        }
        final long now = SystemClock.elapsedRealtime();
        if (badSince == 0) {
            badSince = now;
            return;
        }
        if (now - badSince < BAD_CONNECTION_MS || now - lastFailure < RETRY_AFTER_FAILURE_MS || !mayReplaceActiveProxy()) {
            return;
        }
        switchProxy();
    }

    /** A proxy the user chose is theirs: only a direct connection or our own proxy is replaced. */
    private boolean mayReplaceActiveProxy() {
        SharedConfig.loadProxyList();
        if (!SharedConfig.isProxyEnabled() || SharedConfig.currentProxy == null) {
            return true;
        }
        return isAdded(SharedConfig.currentProxy.settings);
    }

    private void switchProxy() {
        switching = true;
        final int token = ++probeToken;
        Utilities.globalQueue.postRunnable(() -> {
            final ArrayList<ProxySettings> candidates = download();
            AndroidUtilities.runOnUIThread(() -> {
                if (token != probeToken) {
                    return;
                }
                if (candidates.isEmpty()) {
                    fail(KimogramConfig.t("Не удалось скачать список прокси", "Could not download the proxy list"));
                    return;
                }
                probe(token, candidates);
            });
        });
    }

    private void probe(int token, ArrayList<ProxySettings> candidates) {
        final HashMap<ProxySettings, Long> pings = new HashMap<>();
        final int account = UserConfig.selectedAccount;
        final int[] left = {candidates.size()};
        for (ProxySettings settings : candidates) {
            ConnectionsManager.getInstance(account).checkProxy(settings, time -> AndroidUtilities.runOnUIThread(() -> {
                if (token != probeToken) {
                    return;
                }
                if (time > 0) {
                    pings.put(settings, time);
                }
                if (--left[0] == 0) {
                    finish(token, pings);
                }
            }));
        }
        AndroidUtilities.runOnUIThread(() -> finish(token, pings), PING_TIMEOUT_MS);
    }

    private void finish(int token, HashMap<ProxySettings, Long> pings) {
        if (token != probeToken || !switching) {
            return;
        }
        probeToken++;
        ProxySettings best = null;
        long bestPing = Long.MAX_VALUE;
        for (HashMap.Entry<ProxySettings, Long> e : pings.entrySet()) {
            if (e.getValue() < bestPing) {
                bestPing = e.getValue();
                best = e.getKey();
            }
        }
        if (best == null) {
            fail(KimogramConfig.t("Рабочих прокси не нашлось, попробую позже", "No working proxy found, will retry"));
            return;
        }
        apply(best, bestPing);
        switching = false;
        badSince = 0;
        status = "";
    }

    private void fail(String text) {
        switching = false;
        lastFailure = SystemClock.elapsedRealtime();
        status = text;
    }

    private void apply(ProxySettings settings, long ping) {
        removeAdded(settings);
        SharedConfig.ProxyInfo info = SharedConfig.addProxy(new SharedConfig.ProxyInfo(settings));
        info.ping = ping;
        info.available = true;
        info.availableCheckTime = SystemClock.elapsedRealtime();
        Set<String> added = addedKeys();
        added.add(key(settings));
        setAddedKeys(added);

        SharedPreferences.Editor editor = MessagesController.getGlobalMainSettings().edit();
        settings.toSharedPreferences(editor);
        editor.putBoolean("proxy_enabled", true);
        editor.commit();
        SharedConfig.currentProxy = info;
        ConnectionsManager.setProxySettings(true, settings);
        NotificationCenter.getGlobalInstance().postNotificationName(NotificationCenter.proxySettingsChanged);
        FileLog.d("kimogram auto-proxy: switched to " + settings.getAddress() + ":" + settings.getPort() + " ping " + ping);
    }

    /** Removes every proxy auto mode added, except {@code keep}. */
    private void removeAdded(ProxySettings keep) {
        SharedConfig.loadProxyList();
        Set<String> added = addedKeys();
        String keepKey = keep != null ? key(keep) : null;
        boolean changed = false;
        for (SharedConfig.ProxyInfo info : new ArrayList<>(SharedConfig.proxyList)) {
            String k = key(info.settings);
            if (added.contains(k) && !k.equals(keepKey)) {
                SharedConfig.deleteProxy(info);
                changed = true;
            }
        }
        Set<String> left = new HashSet<>();
        if (keepKey != null && added.contains(keepKey)) {
            left.add(keepKey);
        }
        setAddedKeys(left);
        if (changed) {
            NotificationCenter.getGlobalInstance().postNotificationName(NotificationCenter.proxySettingsChanged);
        }
    }

    private static boolean isAdded(ProxySettings settings) {
        return addedKeys().contains(key(settings));
    }

    private static String key(ProxySettings s) {
        return s.getAddress() + ":" + s.getPort();
    }

    private static Set<String> addedKeys() {
        return new HashSet<>(prefs().getStringSet(ADDED_KEY, Collections.emptySet()));
    }

    private static void setAddedKeys(Set<String> keys) {
        prefs().edit().putStringSet(ADDED_KEY, new HashSet<>(keys)).apply();
    }

    private static SharedPreferences prefs() {
        return org.telegram.messenger.ApplicationLoader.applicationContext.getSharedPreferences("kimogram", android.content.Context.MODE_PRIVATE);
    }

    /** Downloads the lists one after another and stops once it has a full batch. Background thread. */
    private static ArrayList<ProxySettings> download() {
        LinkedHashSet<String> seen = new LinkedHashSet<>();
        ArrayList<ProxySettings> result = new ArrayList<>();
        for (String url : LISTS) {
            if (result.size() >= BATCH) {
                break;
            }
            HttpURLConnection connection = null;
            try {
                connection = (HttpURLConnection) new URL(url).openConnection();
                connection.setConnectTimeout(8000);
                connection.setReadTimeout(8000);
                connection.setRequestProperty("User-Agent", "Kimogram");
                if (connection.getResponseCode() != 200) {
                    continue;
                }
                BufferedReader reader = new BufferedReader(new InputStreamReader(connection.getInputStream(), "UTF-8"));
                String line;
                while ((line = reader.readLine()) != null && result.size() < BATCH) {
                    ProxySettings s = parse(line.trim());
                    if (s != null && seen.add(key(s))) {
                        result.add(s);
                    }
                }
                reader.close();
            } catch (Throwable e) {
                FileLog.e(e);
            } finally {
                if (connection != null) {
                    connection.disconnect();
                }
            }
        }
        return result;
    }

    /** Accepts tg://proxy?… and https://t.me/proxy?… lines; only MTProto proxies are kept. */
    static ProxySettings parse(String line) {
        if (TextUtils.isEmpty(line) || !(line.startsWith("tg://proxy") || line.contains("t.me/proxy"))) {
            return null;
        }
        try {
            ProxySettings s = ProxySettings.fromUri(Uri.parse(line));
            if (s == null || s.getType() != ProxySettings.Type.MTPROTO || TextUtils.isEmpty(s.getSecret()) || !s.isValid()) {
                return null;
            }
            return s;
        } catch (Throwable e) {
            return null;
        }
    }
}
