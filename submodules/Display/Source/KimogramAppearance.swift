import Foundation
import UIKit

/// Kimogram: look-and-feel switches that low-level UI code reads directly.
///
/// They live in Display (rather than TelegramCore's `KimogramSettings`) because the glass, avatar
/// and font code that reads them sits below TelegramCore. Values are kept in the standard defaults
/// under `kimogram.appearance.*`, so Kimogram's settings export picks them up too.
public enum KimogramAppearance {
    public static let didChangeNotification = Notification.Name("KimogramAppearanceDidChange")

    private static let glassTransparencyKey = "kimogram.appearance.glassTransparency"
    private static let glassTintKey = "kimogram.appearance.glassTint"
    private static let classicPanelsKey = "kimogram.appearance.classicPanels"
    private static let glassStaticKey = "kimogram.appearance.glassStatic"
    private static let avatarShapeKey = "kimogram.appearance.avatarShape"
    private static let roundedFontKey = "kimogram.appearance.roundedFont"
    private static let noMenuBlurKey = "kimogram.appearance.noMenuBlur"
    private static let noHapticsKey = "kimogram.appearance.noHaptics"

    /// Bumped on every change, so cached views can tell that their look is out of date.
    public private(set) static var generation: Int = 0

    private static func changed() {
        generation += 1
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    // MARK: Glass

    /// 0 is matte, 0.5 is Telegram's own look, 1 is fully clear.
    public static var glassTransparency: CGFloat {
        get {
            if let value = UserDefaults.standard.object(forKey: glassTransparencyKey) as? NSNumber {
                return CGFloat(max(0.0, min(1.0, value.doubleValue)))
            }
            return 0.5
        }
        set {
            UserDefaults.standard.set(Double(max(0.0, min(1.0, newValue))), forKey: glassTransparencyKey)
            changed()
        }
    }

    /// Tints the glass with Kimogram's violet.
    public static var glassTint: Bool {
        get { return UserDefaults.standard.bool(forKey: glassTintKey) }
        set { UserDefaults.standard.set(newValue, forKey: glassTintKey); changed() }
    }

    /// Solid panels instead of glass, close to Telegram before the iOS 26 redesign.
    public static var classicPanels: Bool {
        get { return UserDefaults.standard.bool(forKey: classicPanelsKey) }
        set { UserDefaults.standard.set(newValue, forKey: classicPanelsKey); changed() }
    }

    /// Glass that does not ripple and swell under a finger.
    public static var glassStatic: Bool {
        get { return UserDefaults.standard.bool(forKey: glassStaticKey) }
        set { UserDefaults.standard.set(newValue, forKey: glassStaticKey); changed() }
    }

    /// No blurred backdrop behind context menus.
    public static var noMenuBlur: Bool {
        get { return UserDefaults.standard.bool(forKey: noMenuBlurKey) }
        set { UserDefaults.standard.set(newValue, forKey: noMenuBlurKey); changed() }
    }

    public static let violet = UIColor(red: 0x8a / 255.0, green: 0x5c / 255.0, blue: 0xff / 255.0, alpha: 1.0)

    /// Applies the transparency and tint switches to a glass tint colour.
    ///
    /// `base` is the colour Telegram would use; nil means no tint. Returns the colour to use and
    /// whether the clearer glass style should be used.
    public static func adjustedGlassTint(_ base: UIColor?, isDark: Bool) -> (color: UIColor?, preferClear: Bool) {
        let t = glassTransparency
        var color = base
        if glassTint {
            let source = color ?? UIColor(white: isDark ? 0.0 : 1.0, alpha: isDark ? 0.0 : 0.1)
            var alpha: CGFloat = 0.0
            source.getRed(nil, green: nil, blue: nil, alpha: &alpha)
            color = mix(source.withAlphaComponent(1.0), violet, 0.35).withAlphaComponent(max(alpha, 0.14))
        }
        if abs(t - 0.5) < 0.001 {
            return (color, false)
        }
        if t < 0.5 {
            // Towards matte: raise the tint's opacity up to an almost solid panel.
            let k = (0.5 - t) * 2.0
            let solid = UIColor(white: isDark ? 0.11 : 0.98, alpha: 1.0)
            let source = color ?? solid.withAlphaComponent(0.0)
            var a: CGFloat = 0.0
            source.getRed(nil, green: nil, blue: nil, alpha: &a)
            let target = a + (0.92 - a) * k
            let mixed: UIColor = color == nil ? solid : source.withAlphaComponent(1.0)
            return (mixed.withAlphaComponent(max(a, target)), false)
        } else {
            // Towards clear: fade the tint out, then switch to the clear glass style.
            let k = (t - 0.5) * 2.0
            var a: CGFloat = 0.0
            color?.getRed(nil, green: nil, blue: nil, alpha: &a)
            let faded = color?.withAlphaComponent(a * (1.0 - k))
            return (faded, k > 0.55)
        }
    }

    /// The solid colour a panel takes in classic mode.
    public static func classicPanelColor(isDark: Bool, custom: UIColor?) -> UIColor {
        if let custom {
            var a: CGFloat = 0.0
            custom.getRed(nil, green: nil, blue: nil, alpha: &a)
            if a > 0.3 {
                return custom.withAlphaComponent(1.0)
            }
        }
        return isDark ? UIColor(red: 0.11, green: 0.11, blue: 0.118, alpha: 0.98) : UIColor(red: 0.976, green: 0.976, blue: 0.976, alpha: 0.98)
    }

    private static func mix(_ a: UIColor, _ b: UIColor, _ f: CGFloat) -> UIColor {
        var r1: CGFloat = 0.0, g1: CGFloat = 0.0, b1: CGFloat = 0.0, a1: CGFloat = 0.0
        var r2: CGFloat = 0.0, g2: CGFloat = 0.0, b2: CGFloat = 0.0, a2: CGFloat = 0.0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * f, green: g1 + (g2 - g1) * f, blue: b1 + (b2 - b1) * f, alpha: a1 + (a2 - a1) * f)
    }

    // MARK: Avatars

    public enum AvatarShape: Int, CaseIterable {
        case circle = 0
        case roundedSquare = 1
        case square = 2
    }

    public static var avatarShape: AvatarShape {
        get { return AvatarShape(rawValue: UserDefaults.standard.integer(forKey: avatarShapeKey)) ?? .circle }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: avatarShapeKey); changed() }
    }

    /// Corner radius of an avatar of the given side under the chosen shape.
    public static func avatarCornerRadius(side: CGFloat) -> CGFloat {
        switch avatarShape {
        case .circle:
            return side * 0.5
        case .roundedSquare:
            return side * 0.28
        case .square:
            return side * 0.1
        }
    }

    /// No vibration anywhere in the interface.
    public static var noHaptics: Bool {
        get { return UserDefaults.standard.bool(forKey: noHapticsKey) }
        set { UserDefaults.standard.set(newValue, forKey: noHapticsKey); changed() }
    }

    // MARK: Font

    /// SF Rounded for the interface's system font. Applies after a restart.
    public static var roundedFont: Bool {
        get { return UserDefaults.standard.bool(forKey: roundedFontKey) }
        set { UserDefaults.standard.set(newValue, forKey: roundedFontKey); changed() }
    }
}

/// Kimogram: a short full-screen flourish (a big emoji that pops, glows and floats away) for
/// moments such as turning on ghost mode or locking a chat.
public enum KimogramFlourish {
    public static func play(emoji: String, in window: UIWindow?) {
        guard let window else {
            return
        }
        let container = UIView(frame: window.bounds)
        container.isUserInteractionEnabled = false
        window.addSubview(container)

        let glow = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 220.0, height: 220.0))
        glow.center = CGPoint(x: container.bounds.midX, y: container.bounds.midY)
        glow.backgroundColor = KimogramAppearance.violet.withAlphaComponent(0.35)
        glow.layer.cornerRadius = 110.0
        glow.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
        glow.alpha = 0.0
        container.addSubview(glow)

        let label = UILabel()
        label.text = emoji
        label.font = UIFont.systemFont(ofSize: 110.0)
        label.sizeToFit()
        label.center = glow.center
        label.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
        label.alpha = 0.0
        container.addSubview(label)

        // A ring of small sparkles bursting outwards.
        var sparkles: [UILabel] = []
        for i in 0 ..< 8 {
            let sparkle = UILabel()
            sparkle.text = "✦"
            sparkle.font = UIFont.systemFont(ofSize: 22.0, weight: .bold)
            sparkle.textColor = i % 2 == 0 ? KimogramAppearance.violet : UIColor(red: 1.0, green: 0.82, blue: 0.3, alpha: 1.0)
            sparkle.sizeToFit()
            sparkle.center = glow.center
            sparkle.alpha = 0.0
            container.addSubview(sparkle)
            sparkles.append(sparkle)
        }

        if !KimogramAppearance.noHaptics {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }

        UIView.animate(withDuration: 0.5, delay: 0.0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0.0, options: [], animations: {
            label.alpha = 1.0
            label.transform = .identity
            glow.alpha = 1.0
            glow.transform = .identity
        })
        for (i, sparkle) in sparkles.enumerated() {
            let angle = CGFloat(i) / CGFloat(sparkles.count) * .pi * 2.0
            let distance: CGFloat = 130.0
            UIView.animate(withDuration: 0.7, delay: 0.08, options: [.curveEaseOut], animations: {
                sparkle.alpha = 1.0
                sparkle.center = CGPoint(x: glow.center.x + cos(angle) * distance, y: glow.center.y + sin(angle) * distance)
                sparkle.transform = CGAffineTransform(rotationAngle: angle)
            }, completion: { _ in
                UIView.animate(withDuration: 0.3, animations: {
                    sparkle.alpha = 0.0
                    sparkle.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
                })
            })
        }
        UIView.animate(withDuration: 0.45, delay: 0.75, options: [.curveEaseIn], animations: {
            label.alpha = 0.0
            label.transform = CGAffineTransform(translationX: 0.0, y: -90.0).scaledBy(x: 1.2, y: 1.2)
            glow.alpha = 0.0
            glow.transform = CGAffineTransform(scaleX: 1.6, y: 1.6)
        }, completion: { _ in
            container.removeFromSuperview()
        })
    }
}
