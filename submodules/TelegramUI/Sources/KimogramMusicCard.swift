import Foundation
import UIKit
import SwiftSignalKit
import TelegramCore
import AccountContext

/// Kimogram: "Add the track to your profile?"
///
/// iOS does not let an app see another app's Dynamic Island or what it is playing, so the card
/// appears when a Yandex Music track link is on the clipboard (Share ▸ Copy Link in Yandex Music).
/// The clipboard is only checked for a web link pattern, which shows no paste banner, and each copy
/// is offered once. Adding puts "🎧 Artist — Title" into the profile's bio.
final class KimogramMusicCardController {
    static let shared = KimogramMusicCardController()

    private static let lastChangeCountKey = "kimogram.music.lastChangeCount"
    private static let lastUrlKey = "kimogram.music.lastUrl"

    private weak var currentCard: KimogramMusicCardView?
    private var isChecking = false

    func checkClipboard(context: AccountContext, window: UIWindow?) {
        guard !KimogramSettings.get(.noMusicCard), let window, self.currentCard == nil, !self.isChecking else {
            return
        }
        let pasteboard = UIPasteboard.general
        let changeCount = pasteboard.changeCount
        let defaults = UserDefaults.standard
        if defaults.integer(forKey: KimogramMusicCardController.lastChangeCountKey) == changeCount {
            return
        }
        guard #available(iOS 15.0, *) else {
            return
        }
        self.isChecking = true
        pasteboard.detectValues(for: [\UIPasteboard.DetectedValues.probableWebURL], completionHandler: { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                self.isChecking = false
                defaults.set(changeCount, forKey: KimogramMusicCardController.lastChangeCountKey)
                guard case let .success(values) = result else {
                    return
                }
                let urlString = values.probableWebURL
                guard let url = URL(string: urlString), let host = url.host?.lowercased(), host.contains("music.yandex"), url.path.contains("/track/") else {
                    return
                }
                if defaults.string(forKey: KimogramMusicCardController.lastUrlKey) == urlString {
                    return
                }
                defaults.set(urlString, forKey: KimogramMusicCardController.lastUrlKey)
                self.present(context: context, url: url, window: window)
            }
        })
    }

    private func present(context: AccountContext, url: URL, window: UIWindow) {
        let ru = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode == "ru"
        let card = KimogramMusicCardView(frame: window.bounds, ru: ru)
        card.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(card)
        self.currentCard = card
        card.show()

        KimogramMusicCardController.fetchTrackInfo(url: url, completion: { [weak card] info in
            card?.update(info: info)
        })

        card.add = { [weak card] in
            guard let card else {
                return
            }
            let line = card.profileLine(fallbackUrl: url)
            let _ = (context.engine.accountData.updateAbout(about: line)
            |> deliverOnMainQueue).startStandalone(error: { [weak card] _ in
                card?.showResult(success: false)
            }, completed: { [weak card] in
                card?.showResult(success: true)
            })
        }
    }

    struct TrackInfo {
        var title: String?
        var artist: String?
        var cover: UIImage?
    }

    /// Reads the track page's Open Graph tags (title, artist, cover).
    static func fetchTrackInfo(url: URL, completion: @escaping (TrackInfo) -> Void) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10.0)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request, completionHandler: { data, _, _ in
            var info = TrackInfo()
            if let data, let html = String(data: data, encoding: .utf8) {
                func meta(_ property: String) -> String? {
                    let patterns = [
                        "<meta[^>]*property=\"\(property)\"[^>]*content=\"([^\"]*)\"",
                        "<meta[^>]*content=\"([^\"]*)\"[^>]*property=\"\(property)\""
                    ]
                    for pattern in patterns {
                        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]), let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)), let range = Range(match.range(at: 1), in: html) {
                            let value = String(html[range]).replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#39;", with: "'").trimmingCharacters(in: .whitespacesAndNewlines)
                            if !value.isEmpty {
                                return value
                            }
                        }
                    }
                    return nil
                }
                if var title = meta("og:title") {
                    for marker in [" — слушать", ". Слушать", " слушать онлайн", " - listen", ". Listen"] {
                        if let range = title.range(of: marker, options: [.caseInsensitive]) {
                            title = String(title[title.startIndex ..< range.lowerBound])
                        }
                    }
                    info.title = title
                }
                if let description = meta("og:description") {
                    let first = description.components(separatedBy: CharacterSet(charactersIn: "•·|")).first?.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let first, !first.isEmpty, first.count < 60 {
                        info.artist = first
                    }
                }
                if let imageString = meta("og:image") {
                    var fixed = imageString.hasPrefix("//") ? "https:" + imageString : imageString
                    fixed = fixed.replacingOccurrences(of: "%%", with: "400x400")
                    if let imageUrl = URL(string: fixed), let imageData = try? Data(contentsOf: imageUrl), let image = UIImage(data: imageData) {
                        info.cover = image
                    }
                }
            }
            DispatchQueue.main.async {
                completion(info)
            }
        }).resume()
    }
}

/// The card itself: a dimmed, blurred backdrop and a floating card with the cover, the track and two buttons.
final class KimogramMusicCardView: UIView {
    var add: (() -> Void)?

    private let ru: Bool
    private let dimView = UIView()
    private let cardView: UIVisualEffectView
    private let glowLayer = CAGradientLayer()
    private let coverView = UIImageView()
    private let coverPlaceholder = UILabel()
    private let headerLabel = UILabel()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private let addButton = UIButton(type: .system)
    private let laterButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var info = KimogramMusicCardController.TrackInfo()

    init(frame: CGRect, ru: Bool) {
        self.ru = ru
        self.cardView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
        super.init(frame: frame)

        self.dimView.backgroundColor = UIColor(white: 0.0, alpha: 0.35)
        self.dimView.alpha = 0.0
        self.addSubview(self.dimView)
        self.dimView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.laterPressed)))

        self.cardView.layer.cornerRadius = 30.0
        self.cardView.layer.cornerCurve = .continuous
        self.cardView.clipsToBounds = true
        self.addSubview(self.cardView)

        let violet = UIColor(red: 0x8a / 255.0, green: 0x5c / 255.0, blue: 0xff / 255.0, alpha: 1.0)
        self.glowLayer.colors = [violet.withAlphaComponent(0.55).cgColor, UIColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 0.25).cgColor, UIColor.clear.cgColor]
        self.glowLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
        self.glowLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.cardView.contentView.layer.addSublayer(self.glowLayer)

        self.coverView.contentMode = .scaleAspectFill
        self.coverView.clipsToBounds = true
        self.coverView.layer.cornerRadius = 18.0
        self.coverView.layer.cornerCurve = .continuous
        self.coverView.backgroundColor = violet.withAlphaComponent(0.25)
        self.cardView.contentView.addSubview(self.coverView)

        self.coverPlaceholder.text = "🎧"
        self.coverPlaceholder.font = UIFont.systemFont(ofSize: 54.0)
        self.coverPlaceholder.textAlignment = .center
        self.coverView.addSubview(self.coverPlaceholder)

        self.headerLabel.text = ru ? "ДОБАВИТЬ ТРЕК В ПРОФИЛЬ?" : "ADD THE TRACK TO YOUR PROFILE?"
        self.headerLabel.font = UIFont.systemFont(ofSize: 13.0, weight: .semibold)
        self.headerLabel.textColor = violet
        self.headerLabel.textAlignment = .center
        self.cardView.contentView.addSubview(self.headerLabel)

        self.titleLabel.text = ru ? "Трек из Яндекс Музыки" : "Yandex Music track"
        self.titleLabel.font = UIFont.systemFont(ofSize: 21.0, weight: .bold)
        self.titleLabel.textColor = .label
        self.titleLabel.textAlignment = .center
        self.titleLabel.numberOfLines = 2
        self.cardView.contentView.addSubview(self.titleLabel)

        self.artistLabel.text = ru ? "Загружаю название…" : "Loading the title…"
        self.artistLabel.font = UIFont.systemFont(ofSize: 15.0)
        self.artistLabel.textColor = .secondaryLabel
        self.artistLabel.textAlignment = .center
        self.cardView.contentView.addSubview(self.artistLabel)

        self.addButton.setTitle(ru ? "Добавить в профиль" : "Add to Profile", for: .normal)
        self.addButton.titleLabel?.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        self.addButton.setTitleColor(.white, for: .normal)
        self.addButton.backgroundColor = violet
        self.addButton.layer.cornerRadius = 25.0
        self.addButton.layer.cornerCurve = .continuous
        self.addButton.addTarget(self, action: #selector(self.addPressed), for: .touchUpInside)
        self.cardView.contentView.addSubview(self.addButton)

        self.spinner.color = .white
        self.spinner.hidesWhenStopped = true
        self.addButton.addSubview(self.spinner)

        self.laterButton.setTitle(ru ? "Не сейчас" : "Not Now", for: .normal)
        self.laterButton.titleLabel?.font = UIFont.systemFont(ofSize: 17.0)
        self.laterButton.setTitleColor(.secondaryLabel, for: .normal)
        self.laterButton.addTarget(self, action: #selector(self.laterPressed), for: .touchUpInside)
        self.cardView.contentView.addSubview(self.laterButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.dimView.frame = self.bounds
        let width = min(self.bounds.width - 32.0, 380.0)
        let height: CGFloat = 400.0
        let bottomInset = max(self.safeAreaInsets.bottom, 16.0)
        self.cardView.bounds = CGRect(x: 0.0, y: 0.0, width: width, height: height)
        self.cardView.center = CGPoint(x: self.bounds.midX, y: self.bounds.height - bottomInset - height * 0.5)
        self.glowLayer.frame = CGRect(x: 0.0, y: 0.0, width: width, height: height * 0.6)
        let coverSide: CGFloat = 128.0
        self.coverView.frame = CGRect(x: (width - coverSide) * 0.5, y: 24.0, width: coverSide, height: coverSide)
        self.coverPlaceholder.frame = self.coverView.bounds
        self.headerLabel.frame = CGRect(x: 20.0, y: 168.0, width: width - 40.0, height: 18.0)
        self.titleLabel.frame = CGRect(x: 20.0, y: 192.0, width: width - 40.0, height: 54.0)
        self.artistLabel.frame = CGRect(x: 20.0, y: 248.0, width: width - 40.0, height: 20.0)
        self.addButton.frame = CGRect(x: 20.0, y: 284.0, width: width - 40.0, height: 50.0)
        self.spinner.center = CGPoint(x: self.addButton.bounds.width - 30.0, y: self.addButton.bounds.midY)
        self.laterButton.frame = CGRect(x: 20.0, y: 342.0, width: width - 40.0, height: 44.0)
    }

    func show() {
        self.layoutIfNeeded()
        self.cardView.transform = CGAffineTransform(translationX: 0.0, y: 460.0).scaledBy(x: 0.92, y: 0.92)
        UIView.animate(withDuration: 0.6, delay: 0.0, usingSpringWithDamping: 0.78, initialSpringVelocity: 0.0, options: [.allowUserInteraction], animations: {
            self.dimView.alpha = 1.0
            self.cardView.transform = .identity
        })
        self.coverView.layer.add(KimogramMusicCardView.pulseAnimation(), forKey: "pulse")
    }

    private static func pulseAnimation() -> CAAnimation {
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = 1.0
        animation.toValue = 1.04
        animation.duration = 1.2
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return animation
    }

    func update(info: KimogramMusicCardController.TrackInfo) {
        self.info = info
        UIView.transition(with: self.cardView, duration: 0.3, options: [.transitionCrossDissolve, .allowUserInteraction], animations: {
            if let title = info.title {
                self.titleLabel.text = title
            }
            self.artistLabel.text = info.artist ?? (self.ru ? "Яндекс Музыка" : "Yandex Music")
            if let cover = info.cover {
                self.coverView.image = cover
                self.coverPlaceholder.isHidden = true
            }
        })
    }

    /// The bio line: "🎧 Artist — Title", cut to the 70 characters a bio allows.
    func profileLine(fallbackUrl: URL) -> String {
        var text: String
        if let title = self.info.title {
            if let artist = self.info.artist, !title.contains(artist) {
                text = "🎧 " + artist + " — " + title
            } else {
                text = "🎧 " + title
            }
        } else {
            text = "🎧 " + (fallbackUrl.host ?? "") + fallbackUrl.path
        }
        if text.count > 70 {
            text = String(text.prefix(69)) + "…"
        }
        return text
    }

    @objc private func addPressed() {
        self.addButton.isEnabled = false
        self.spinner.startAnimating()
        self.add?()
    }

    func showResult(success: Bool) {
        self.spinner.stopAnimating()
        if success {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            self.addButton.setTitle(self.ru ? "Добавлено в профиль ✓" : "Added to Profile ✓", for: .normal)
            self.addButton.backgroundColor = UIColor(red: 0.2, green: 0.75, blue: 0.4, alpha: 1.0)
            UIView.animate(withDuration: 0.15, animations: {
                self.addButton.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
            }, completion: { _ in
                UIView.animate(withDuration: 0.2, animations: {
                    self.addButton.transform = .identity
                })
            })
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: { [weak self] in
                self?.dismiss()
            })
        } else {
            self.addButton.isEnabled = true
            self.addButton.setTitle(self.ru ? "Не получилось, ещё раз" : "Failed, Try Again", for: .normal)
        }
    }

    @objc private func laterPressed() {
        self.dismiss()
    }

    private func dismiss() {
        UIView.animate(withDuration: 0.3, delay: 0.0, options: [.curveEaseIn], animations: {
            self.dimView.alpha = 0.0
            self.cardView.transform = CGAffineTransform(translationX: 0.0, y: 460.0)
        }, completion: { _ in
            self.removeFromSuperview()
        })
    }
}
