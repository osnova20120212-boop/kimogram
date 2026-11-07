import Foundation
import SwiftSignalKit
import TelegramCore
import MtProtoKit
import Display
import AccountContext
import PresentationDataUtils

/// Kimogram auto-proxy.
///
/// When enabled, it watches the connection of the current network (logged in or not). If the
/// app cannot reach Telegram for a while, it downloads public lists of free MTProto proxies,
/// pings a batch of them through Telegram's own proxy check, and switches to the fastest one.
/// If that proxy stops working later, the same thing happens again with a new proxy.
///
/// It only ever replaces a proxy it added itself: a proxy the user set up by hand is never
/// touched. Turning the feature off removes every proxy it added.
///
/// All state lives on the main queue.
public final class KimogramAutoProxy {
    public static let shared = KimogramAutoProxy()

    private static let enabledKey = "kimogram.autoProxy.enabled"
    private static let askedKey = "kimogram.autoProxy.asked"
    private static let addedKey = "kimogram.autoProxy.added"
    private static let cachedListKey = "kimogram.autoProxy.cachedList"

    /// Kimogram's own list (refreshed and checked by a GitHub Action every 30 minutes) comes
    /// first, through two mirrors; the raw public lists are the fallback.
    private static let listUrls: [String] = [
        "https://raw.githubusercontent.com/osnova20120212-boop/kimogram/proxies/list.txt",
        "https://cdn.jsdelivr.net/gh/osnova20120212-boop/kimogram@proxies/list.txt",
        "https://raw.githubusercontent.com/Argh94/Proxy-List/main/MTProto.txt",
        "https://raw.githubusercontent.com/SoliSpirit/mtproto/master/all_proxies.txt"
    ]

    /// How long the connection may stay in "connecting" before the proxy is replaced.
    private static let stuckTimeout: Double = 12.0
    /// How long every candidate gets to answer the ping.
    private static let probeTimeout: Double = 8.0
    private static let probeBatchSize = 30
    private static let listLifetime: Double = 15.0 * 60.0
    private static let badProxyLifetime: Double = 10.0 * 60.0

    private let enabledValue: ValuePromise<Bool>

    private weak var sharedContext: SharedAccountContext?
    private weak var network: Network?
    private let statusDisposable = MetaDisposable()
    private let settingsDisposable = MetaDisposable()
    private let probeDisposable = MetaDisposable()
    private var probeContext: ProxyServersStatuses?
    private var probeToken = 0
    private var probeBatch: [ProxyServerSettings] = []
    private var probeLatest: [ProxyServerSettings: ProxyServerStatus] = [:]
    private var timer: SwiftSignalKit.Timer?

    private var currentSettings: ProxySettings = ProxySettings.defaultSettings
    private var isConnecting = false
    private var connectingSince: Double?
    private var isSwitching = false
    private var badUntil: [String: Double] = [:]
    private var candidates: [ProxyServerSettings] = []
    private var candidatesTimestamp: Double = 0.0

    private init() {
        self.enabledValue = ValuePromise(UserDefaults.standard.bool(forKey: KimogramAutoProxy.enabledKey), ignoreRepeated: true)
    }

    // MARK: - Public state

    public var isEnabled: Bool {
        return UserDefaults.standard.bool(forKey: KimogramAutoProxy.enabledKey)
    }

    public var enabled: Signal<Bool, NoError> {
        return self.enabledValue.get()
    }

    public static var isRussian: Bool {
        let language = Locale.preferredLanguages.first ?? ""
        return language.hasPrefix("ru") || language.hasPrefix("uk") || language.hasPrefix("be")
    }

    public static var toggleTitle: String {
        return isRussian ? "Авто-прокси Kimogram" : "Kimogram Auto Proxy"
    }

    public static var toggleInfo: String {
        if isRussian {
            return "Если подключиться не получается, Kimogram сам найдёт бесплатный прокси, проверит его и включит. Когда прокси перестаёт работать, он сразу заменяется новым. Сообщения остаются зашифрованными, но владелец прокси видит ваш IP-адрес."
        } else {
            return "If Kimogram cannot connect, it finds a free proxy, checks it and turns it on. When the proxy stops working, it is replaced right away. Messages stay encrypted, but the proxy owner can see your IP address."
        }
    }

    public static var modeHeaderTitle: String {
        return isRussian ? "ТИП ПРОКСИ" : "PROXY TYPE"
    }

    public static var manualTitle: String {
        return isRussian ? "Свой прокси" : "My Own Proxy"
    }

    public static var autoModeSubtitle: String {
        return isRussian ? "Сам находит и меняет прокси" : "Finds and switches proxies for you"
    }

    public static var manualModeSubtitle: String {
        return isRussian ? "Вставьте адрес своего прокси" : "Add the address of your own proxy"
    }

    public static var manualInfo: String {
        if isRussian {
            return "Добавьте свой прокси ниже: вставьте ссылку tg://proxy или введите адрес вручную."
        } else {
            return "Add your own proxy below: paste a tg://proxy link or enter the address by hand."
        }
    }

    /// One line on what auto mode is doing right now.
    public static func statusText(proxySettings: ProxySettings, connectionStatus: ConnectionStatus, ping: Double?) -> String {
        let ru = isRussian
        var viaProxy: String?
        if proxySettings.enabled, let active = proxySettings.activeServer {
            viaProxy = "\(active.host):\(active.port)"
        }
        switch connectionStatus {
        case .waitingForNetwork:
            return ru ? "Сейчас: нет интернета на устройстве." : "Now: the device is offline."
        case .connecting:
            return ru ? "Сейчас: ищу рабочий прокси…" : "Now: looking for a working proxy…"
        case .updating, .online:
            if let viaProxy {
                var text = ru ? "Сейчас: подключено через прокси \(viaProxy)" : "Now: connected through proxy \(viaProxy)"
                if let ping {
                    text += ru ? ", пинг \(Int(ping * 1000.0)) мс" : ", ping \(Int(ping * 1000.0)) ms"
                }
                return text + "."
            } else {
                return ru ? "Сейчас: подключено напрямую, прокси не нужен." : "Now: connected directly, no proxy needed."
            }
        }
    }

    public static func isAutoAdded(_ server: ProxyServerSettings) -> Bool {
        return addedKeys().contains(serverKey(server))
    }

    // MARK: - Lifecycle

    /// Called from the app delegate with the network of the current context (logged in or
    /// not). Passing nil stops watching.
    public func attach(sharedContext: SharedAccountContext, network: Network?) {
        assert(Queue.mainQueue().isCurrent())
        self.sharedContext = sharedContext

        if let current = self.network, let network, current === network {
            return
        }
        self.network = network
        self.isConnecting = false
        self.connectingSince = nil
        self.cancelProbe()

        self.settingsDisposable.set((sharedContext.accountManager.sharedData(keys: [SharedDataKeys.proxySettings])
        |> deliverOnMainQueue).start(next: { [weak self] sharedData in
            guard let self else {
                return
            }
            self.currentSettings = sharedData.entries[SharedDataKeys.proxySettings]?.get(ProxySettings.self) ?? ProxySettings.defaultSettings
        }))

        guard let network else {
            self.statusDisposable.set(nil)
            self.timer?.invalidate()
            self.timer = nil
            return
        }

        self.statusDisposable.set((network.connectionStatus
        |> deliverOnMainQueue).start(next: { [weak self] status in
            self?.connectionStatusUpdated(status)
        }))

        if self.timer == nil {
            let timer = SwiftSignalKit.Timer(timeout: 3.0, repeat: true, completion: { [weak self] in
                self?.tick()
            }, queue: Queue.mainQueue())
            self.timer = timer
            timer.start()
        }
    }

    public func setEnabled(_ value: Bool) {
        assert(Queue.mainQueue().isCurrent())
        UserDefaults.standard.set(value, forKey: KimogramAutoProxy.enabledKey)
        UserDefaults.standard.set(true, forKey: KimogramAutoProxy.askedKey)
        self.enabledValue.set(value)

        if value {
            // Turned on by hand while the app is stuck: do not make the user wait.
            if self.isConnecting {
                self.switchProxy()
            }
        } else {
            self.cancelProbe()
            self.removeAddedServers()
        }
    }

    /// The first time a not-logged-in user sees the login screen, offer to turn the feature on.
    public func presentLoginOfferIfNeeded(sharedContext: SharedAccountContext, present: @escaping (ViewController) -> Void) {
        if UserDefaults.standard.bool(forKey: KimogramAutoProxy.askedKey) {
            return
        }
        UserDefaults.standard.set(true, forKey: KimogramAutoProxy.askedKey)

        let ru = KimogramAutoProxy.isRussian
        let title = ru ? "Включить авто-прокси?" : "Turn on Auto Proxy?"
        let text = ru
            ? "Если в вашей стране блокируют мессенджер или он плохо подключается, Kimogram сам подберёт бесплатный прокси и будет менять его, если он перестанет работать.\n\nВладелец прокси видит ваш IP-адрес, но не ваши сообщения. Выключить можно в Настройки ▸ Настройки Kimogram ▸ Прокси."
            : "If messaging is blocked in your country or connects poorly, Kimogram picks a free proxy for you and replaces it whenever it stops working.\n\nThe proxy owner can see your IP address, but not your messages. You can turn it off in Settings ▸ Kimogram Settings ▸ Proxy."
        let alert = textAlertController(sharedContext: sharedContext, title: title, text: text, actions: [
            TextAlertAction(type: .genericAction, title: ru ? "Не сейчас" : "Not Now", action: {}),
            TextAlertAction(type: .defaultAction, title: ru ? "Включить" : "Turn On", action: { [weak self] in
                self?.setEnabled(true)
            })
        ], actionLayout: .vertical)
        present(alert)
    }

    // MARK: - Watching

    private func connectionStatusUpdated(_ status: ConnectionStatus) {
        switch status {
        case .connecting:
            if !self.isConnecting {
                self.isConnecting = true
                self.connectingSince = CFAbsoluteTimeGetCurrent()
            }
        case .online, .updating, .waitingForNetwork:
            // Waiting for network means the device itself is offline: no proxy helps there.
            self.isConnecting = false
            self.connectingSince = nil
        }
    }

    private func tick() {
        guard self.isEnabled, self.network != nil, self.isConnecting, !self.isSwitching else {
            return
        }
        guard let connectingSince = self.connectingSince, CFAbsoluteTimeGetCurrent() - connectingSince >= KimogramAutoProxy.stuckTimeout else {
            return
        }
        if !self.mayReplaceActiveProxy() {
            return
        }
        self.switchProxy()
    }

    /// A proxy the user chose is theirs: only a direct connection or our own proxy is replaced.
    private func mayReplaceActiveProxy() -> Bool {
        guard self.currentSettings.enabled, let active = self.currentSettings.activeServer else {
            return true
        }
        return KimogramAutoProxy.isAutoAdded(active)
    }

    // MARK: - Switching

    private func switchProxy() {
        guard !self.isSwitching, let network = self.network, self.mayReplaceActiveProxy() else {
            return
        }
        self.isSwitching = true

        let now = CFAbsoluteTimeGetCurrent()
        if self.currentSettings.enabled, let active = self.currentSettings.activeServer, KimogramAutoProxy.isAutoAdded(active) {
            self.badUntil[KimogramAutoProxy.serverKey(active)] = now + KimogramAutoProxy.badProxyLifetime
        }

        self.loadCandidates(completion: { [weak self] candidates in
            guard let self else {
                return
            }
            guard self.isEnabled, let currentNetwork = self.network, currentNetwork === network else {
                self.isSwitching = false
                return
            }
            let now = CFAbsoluteTimeGetCurrent()
            let batch = Array(candidates.filter { server in
                if let until = self.badUntil[KimogramAutoProxy.serverKey(server)], until > now {
                    return false
                }
                return true
            }.shuffled().prefix(KimogramAutoProxy.probeBatchSize))

            if batch.isEmpty {
                // Everything known is marked bad: forget the marks and try again later.
                self.badUntil.removeAll()
                self.finishSwitching()
                return
            }
            self.probe(batch, network: network)
        })
    }

    private func probe(_ batch: [ProxyServerSettings], network: Network) {
        self.probeToken += 1
        let token = self.probeToken
        self.probeBatch = batch
        self.probeLatest = [:]

        let context = ProxyServersStatuses(network: network, servers: .single(batch))
        self.probeContext = context

        self.probeDisposable.set((context.statuses()
        |> deliverOnMainQueue).start(next: { [weak self] statuses in
            guard let self, self.probeToken == token else {
                return
            }
            self.probeLatest = statuses
            var answered = 0
            for server in batch {
                if let status = statuses[server], status != .checking {
                    answered += 1
                }
            }
            if answered == batch.count {
                self.finishProbe(token: token)
            }
        }))

        Queue.mainQueue().after(KimogramAutoProxy.probeTimeout, { [weak self] in
            self?.finishProbe(token: token)
        })
    }

    private func finishProbe(token: Int) {
        guard self.probeToken == token, self.probeContext != nil else {
            return
        }
        let batch = self.probeBatch
        let statuses = self.probeLatest
        self.probeDisposable.set(nil)
        self.probeContext = nil
        self.probeBatch = []
        self.probeLatest = [:]
        self.pickBest(batch: batch, statuses: statuses)
    }

    private func pickBest(batch: [ProxyServerSettings], statuses: [ProxyServerSettings: ProxyServerStatus]) {
        let now = CFAbsoluteTimeGetCurrent()
        var best: (server: ProxyServerSettings, rtt: Double)?
        for server in batch {
            if case let .available(rtt) = statuses[server] ?? .checking {
                if best == nil || rtt < best!.rtt {
                    best = (server, rtt)
                }
            } else {
                self.badUntil[KimogramAutoProxy.serverKey(server)] = now + KimogramAutoProxy.badProxyLifetime
            }
        }

        guard let best, self.isEnabled, let sharedContext = self.sharedContext, self.mayReplaceActiveProxy() else {
            self.finishSwitching()
            return
        }

        let server = best.server
        let previousAdded = KimogramAutoProxy.addedKeys()
        KimogramAutoProxy.setAddedKeys([KimogramAutoProxy.serverKey(server)])

        let _ = (updateProxySettingsInteractively(accountManager: sharedContext.accountManager, { current in
            var current = current
            // Keep the list tidy: an auto proxy that was replaced goes away, unless the user
            // saved the same server by hand.
            current.servers.removeAll(where: { previousAdded.contains(KimogramAutoProxy.serverKey($0)) && $0 != server })
            if !current.servers.contains(server) {
                current.servers.insert(server, at: 0)
            }
            current.activeServer = server
            current.enabled = true
            return current
        })
        |> deliverOnMainQueue).start(completed: { [weak self] in
            self?.finishSwitching()
        })
    }

    private func finishSwitching() {
        self.isSwitching = false
        // Give the new proxy a full timeout before judging it.
        if self.isConnecting {
            self.connectingSince = CFAbsoluteTimeGetCurrent()
        }
    }

    private func cancelProbe() {
        self.probeToken += 1
        self.probeDisposable.set(nil)
        self.probeContext = nil
        self.isSwitching = false
    }

    private func removeAddedServers() {
        guard let sharedContext = self.sharedContext else {
            return
        }
        let added = KimogramAutoProxy.addedKeys()
        KimogramAutoProxy.setAddedKeys([])
        if added.isEmpty {
            return
        }
        let _ = updateProxySettingsInteractively(accountManager: sharedContext.accountManager, { current in
            var current = current
            current.servers.removeAll(where: { added.contains(KimogramAutoProxy.serverKey($0)) })
            if let active = current.activeServer, added.contains(KimogramAutoProxy.serverKey(active)) {
                current.activeServer = nil
                current.enabled = false
            }
            return current
        }).start()
    }

    // MARK: - Lists

    private func loadCandidates(completion: @escaping ([ProxyServerSettings]) -> Void) {
        let now = CFAbsoluteTimeGetCurrent()
        if !self.candidates.isEmpty && now - self.candidatesTimestamp < KimogramAutoProxy.listLifetime {
            completion(self.candidates)
            return
        }
        KimogramAutoProxy.download(urls: KimogramAutoProxy.listUrls, collected: [], completion: { [weak self] lines in
            Queue.mainQueue().async {
                guard let self else {
                    return
                }
                var lines = lines
                if lines.isEmpty {
                    lines = UserDefaults.standard.stringArray(forKey: KimogramAutoProxy.cachedListKey) ?? []
                } else {
                    UserDefaults.standard.set(Array(lines.prefix(500)), forKey: KimogramAutoProxy.cachedListKey)
                }
                var seen = Set<String>()
                var result: [ProxyServerSettings] = []
                for line in lines {
                    if let server = KimogramAutoProxy.parseProxyLine(line), seen.insert(KimogramAutoProxy.serverKey(server)).inserted {
                        result.append(server)
                    }
                }
                if !result.isEmpty {
                    self.candidates = result
                    self.candidatesTimestamp = CFAbsoluteTimeGetCurrent()
                }
                completion(result)
            }
        })
    }

    /// Downloads the lists one after another and stops at the first that gives enough proxies.
    private static func download(urls: [String], collected: [String], completion: @escaping ([String]) -> Void) {
        guard let first = urls.first, let url = URL(string: first) else {
            completion(collected)
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10.0)
        request.httpMethod = "GET"
        let task = URLSession.shared.dataTask(with: request, completionHandler: { data, response, _ in
            var collected = collected
            if let data, let response = response as? HTTPURLResponse, response.statusCode == 200, let text = String(data: data, encoding: .utf8) {
                collected.append(contentsOf: text.components(separatedBy: .newlines).filter { !$0.isEmpty })
            }
            if collected.count >= 40 {
                completion(collected)
            } else {
                KimogramAutoProxy.download(urls: Array(urls.dropFirst()), collected: collected, completion: completion)
            }
        })
        task.resume()
    }

    /// Accepts `tg://proxy?…` and `https://t.me/proxy?…` lines. Only MTProto proxies are kept:
    /// a SOCKS5 proxy without a password is rarely alive and never obfuscated.
    static func parseProxyLine(_ line: String) -> ProxyServerSettings? {
        let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let queryStart = line.range(of: "proxy?") else {
            return nil
        }
        guard let components = URLComponents(string: "tg://" + String(line[queryStart.lowerBound...])), let items = components.queryItems else {
            return nil
        }
        var host: String?
        var port: Int32?
        var secret: Data?
        for item in items {
            guard let value = item.value, !value.isEmpty else {
                continue
            }
            switch item.name {
            case "server":
                var value = value
                while value.hasSuffix(".") {
                    value.removeLast()
                }
                host = value
            case "port":
                port = Int32(value)
            case "secret":
                secret = MTProxySecret.parse(value)?.serialize()
            default:
                break
            }
        }
        guard let host, !host.isEmpty, let port, port > 0, port <= 65535, let secret else {
            return nil
        }
        return ProxyServerSettings(host: host, port: port, connection: .mtp(secret: secret))
    }

    // MARK: - Storage helpers

    private static func serverKey(_ server: ProxyServerSettings) -> String {
        return "\(server.host.lowercased()):\(server.port)"
    }

    private static func addedKeys() -> Set<String> {
        return Set(UserDefaults.standard.stringArray(forKey: KimogramAutoProxy.addedKey) ?? [])
    }

    private static func setAddedKeys(_ keys: Set<String>) {
        UserDefaults.standard.set(Array(keys), forKey: KimogramAutoProxy.addedKey)
    }
}
