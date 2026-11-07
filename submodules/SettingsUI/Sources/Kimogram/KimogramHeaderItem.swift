import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI

/// The hero at the top of Kimogram Settings: the crystal logo floating over a soft violet glow,
/// the name and a one-line tagline.
final class KimogramHeaderItem: ListViewItem, ItemListItem {
    let theme: PresentationTheme
    let title: String
    let subtitle: String
    let sectionId: ItemListSectionId

    init(theme: PresentationTheme, title: String, subtitle: String, sectionId: ItemListSectionId) {
        self.theme = theme
        self.title = title
        self.subtitle = subtitle
        self.sectionId = sectionId
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = KimogramHeaderItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))

            node.contentSize = layout.contentSize
            node.insets = layout.insets

            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply() })
                })
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, neighbors: ListViewItemNeighbors, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            guard let nodeValue = node() as? KimogramHeaderItemNode else {
                assertionFailure()
                return
            }

            let makeLayout = nodeValue.asyncLayout()

            async {
                let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
                Queue.mainQueue().async {
                    completion(layout, { _ in
                        apply()
                    })
                }
            }
        }
    }
}

final class KimogramHeaderItemNode: ListViewItemNode {
    private let glowNode: ASImageNode
    private let logoNode: ASImageNode
    private let titleNode: ImmediateTextNode
    private let subtitleNode: ImmediateTextNode

    private var item: KimogramHeaderItem?
    private var didStartAnimations = false

    private static let logoSize: CGFloat = 96.0
    private static let glowSize: CGFloat = 190.0

    private static let glowImage: UIImage? = generateImage(CGSize(width: KimogramHeaderItemNode.glowSize, height: KimogramHeaderItemNode.glowSize), rotatedContext: { size, context in
        context.clear(CGRect(origin: CGPoint(), size: size))
        let colors: [CGColor] = [
            UIColor(rgb: 0x8a5cff, alpha: 0.55).cgColor,
            UIColor(rgb: 0x6a3de8, alpha: 0.18).cgColor,
            UIColor(rgb: 0x6a3de8, alpha: 0.0).cgColor
        ]
        var locations: [CGFloat] = [0.0, 0.55, 1.0]
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: &locations) else {
            return
        }
        let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0.0, endCenter: center, endRadius: size.width / 2.0, options: [])
    })

    init() {
        self.glowNode = ASImageNode()
        self.glowNode.isLayerBacked = true
        self.glowNode.displaysAsynchronously = false
        self.glowNode.image = KimogramHeaderItemNode.glowImage

        self.logoNode = ASImageNode()
        self.logoNode.isLayerBacked = true
        self.logoNode.displaysAsynchronously = false
        self.logoNode.image = UIImage(bundleImageName: "Settings/KimogramLogo")

        self.titleNode = ImmediateTextNode()
        self.titleNode.displaysAsynchronously = false
        self.titleNode.textAlignment = .center

        self.subtitleNode = ImmediateTextNode()
        self.subtitleNode.displaysAsynchronously = false
        self.subtitleNode.textAlignment = .center
        self.subtitleNode.maximumNumberOfLines = 2

        super.init(layerBacked: false)

        self.addSubnode(self.glowNode)
        self.addSubnode(self.logoNode)
        self.addSubnode(self.titleNode)
        self.addSubnode(self.subtitleNode)
    }

    func asyncLayout() -> (_ item: KimogramHeaderItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        return { [weak self] item, params, neighbors in
            let height: CGFloat = 214.0
            let contentSize = CGSize(width: params.width, height: height)
            let insets = itemListNeighborsGroupedInsets(neighbors, params)
            let layout = ListViewItemNodeLayout(contentSize: contentSize, insets: insets)

            return (layout, {
                guard let self else {
                    return
                }
                self.item = item

                let width = params.width
                let logoSize = KimogramHeaderItemNode.logoSize
                let glowSize = KimogramHeaderItemNode.glowSize
                let logoFrame = CGRect(x: floor((width - logoSize) / 2.0), y: 8.0, width: logoSize, height: logoSize)
                self.logoNode.frame = logoFrame
                self.glowNode.frame = CGRect(x: floor((width - glowSize) / 2.0), y: logoFrame.midY - glowSize / 2.0, width: glowSize, height: glowSize)

                self.titleNode.attributedText = NSAttributedString(string: item.title, font: Font.bold(26.0), textColor: item.theme.list.itemPrimaryTextColor)
                self.subtitleNode.attributedText = NSAttributedString(string: item.subtitle, font: Font.regular(15.0), textColor: item.theme.list.freeTextColor)

                let textWidth = width - params.leftInset - params.rightInset - 48.0
                let titleSize = self.titleNode.updateLayout(CGSize(width: textWidth, height: 40.0))
                let subtitleSize = self.subtitleNode.updateLayout(CGSize(width: textWidth, height: 60.0))
                self.titleNode.frame = CGRect(x: floor((width - titleSize.width) / 2.0), y: logoFrame.maxY + 16.0, width: titleSize.width, height: titleSize.height)
                self.subtitleNode.frame = CGRect(x: floor((width - subtitleSize.width) / 2.0), y: logoFrame.maxY + 16.0 + titleSize.height + 4.0, width: subtitleSize.width, height: subtitleSize.height)

                if !self.didStartAnimations {
                    self.didStartAnimations = true
                    self.startAnimations()
                }
            })
        }
    }

    /// A slow float for the crystal and a breathing glow behind it.
    private func startAnimations() {
        let float = CABasicAnimation(keyPath: "transform.translation.y")
        float.fromValue = -4.0 as NSNumber
        float.toValue = 4.0 as NSNumber
        float.duration = 2.6
        float.autoreverses = true
        float.repeatCount = .infinity
        float.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        float.isRemovedOnCompletion = false
        self.logoNode.layer.add(float, forKey: "kimogramFloat")

        let breathe = CABasicAnimation(keyPath: "transform.scale")
        breathe.fromValue = 0.92 as NSNumber
        breathe.toValue = 1.08 as NSNumber
        breathe.duration = 2.6
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        breathe.isRemovedOnCompletion = false
        self.glowNode.layer.add(breathe, forKey: "kimogramBreathe")

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.7 as NSNumber
        fade.toValue = 1.0 as NSNumber
        fade.duration = 2.6
        fade.autoreverses = true
        fade.repeatCount = .infinity
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        fade.isRemovedOnCompletion = false
        self.glowNode.layer.add(fade, forKey: "kimogramFade")
    }

    override func animateInsertion(_ currentTimestamp: Double, duration: Double, options: ListViewItemAnimationOptions) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.4)
        self.logoNode.layer.animateSpring(from: 0.6 as NSNumber, to: 1.0 as NSNumber, keyPath: "transform.scale", duration: 0.6)
    }

    override func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false)
    }
}
