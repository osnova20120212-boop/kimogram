import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramPresentationData
import LegacyComponents
import ItemListUI
import PresentationDataUtils

/// Kimogram: a stepped slider row with a caption under each end (e.g. "Matte" … "Clear").
final class KimogramSliderItem: ListViewItem, ItemListItem {
    let theme: PresentationTheme
    let value: Int
    let positions: Int
    let leftTitle: String
    let rightTitle: String
    let sectionId: ItemListSectionId
    let updated: (Int) -> Void

    init(theme: PresentationTheme, value: Int, positions: Int, leftTitle: String, rightTitle: String, sectionId: ItemListSectionId, updated: @escaping (Int) -> Void) {
        self.theme = theme
        self.value = value
        self.positions = positions
        self.leftTitle = leftTitle
        self.rightTitle = rightTitle
        self.sectionId = sectionId
        self.updated = updated
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = KimogramSliderItemNode()
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
            if let nodeValue = node() as? KimogramSliderItemNode {
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
}

final class KimogramSliderItemNode: ListViewItemNode, ItemListItemNode {
    private let backgroundNode: ASDisplayNode
    private let topStripeNode: ASDisplayNode
    private let bottomStripeNode: ASDisplayNode
    private let maskNode: ASImageNode
    private let leftTextNode: ImmediateTextNode
    private let rightTextNode: ImmediateTextNode

    private var sliderView: TGPhotoEditorSliderView?
    private var item: KimogramSliderItem?
    private var layoutParams: ListViewItemLayoutParams?

    var tag: ItemListItemTag? {
        return nil
    }

    init() {
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isLayerBacked = true
        self.topStripeNode = ASDisplayNode()
        self.topStripeNode.isLayerBacked = true
        self.bottomStripeNode = ASDisplayNode()
        self.bottomStripeNode.isLayerBacked = true
        self.maskNode = ASImageNode()
        self.leftTextNode = ImmediateTextNode()
        self.rightTextNode = ImmediateTextNode()

        super.init(layerBacked: false)

        self.addSubnode(self.leftTextNode)
        self.addSubnode(self.rightTextNode)
    }

    override func didLoad() {
        super.didLoad()

        self.accessibilityTraits = [.adjustable]

        let sliderView = TGPhotoEditorSliderView()
        sliderView.enablePanHandling = true
        sliderView.trackCornerRadius = 2.0
        sliderView.lineSize = 4.0
        sliderView.dotSize = 6.0
        sliderView.minimumValue = 0.0
        sliderView.startValue = 0.0
        sliderView.useLinesForPositions = true
        sliderView.disablesInteractiveTransitionGestureRecognizer = true
        if let item = self.item, let params = self.layoutParams {
            self.configure(sliderView: sliderView, item: item, params: params, setValue: true, themeUpdated: true)
        }
        self.view.addSubview(sliderView)
        sliderView.addTarget(self, action: #selector(self.sliderValueChanged), for: .valueChanged)
        self.sliderView = sliderView
    }

    private func configure(sliderView: TGPhotoEditorSliderView, item: KimogramSliderItem, params: ListViewItemLayoutParams, setValue: Bool, themeUpdated: Bool) {
        sliderView.maximumValue = CGFloat(max(1, item.positions - 1))
        sliderView.positionsCount = item.positions
        if themeUpdated {
            sliderView.backgroundColor = item.theme.list.itemBlocksBackgroundColor
            sliderView.backColor = item.theme.list.itemSwitchColors.frameColor
            sliderView.trackColor = item.theme.list.itemAccentColor
            sliderView.knobImage = PresentationResourcesItemList.knobImage(item.theme)
        }
        if setValue {
            sliderView.value = CGFloat(item.value)
        }
        sliderView.frame = CGRect(origin: CGPoint(x: params.leftInset + 16.0, y: 6.0), size: CGSize(width: params.width - params.leftInset - params.rightInset - 32.0, height: 44.0))
    }

    func asyncLayout() -> (_ item: KimogramSliderItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        let currentItem = self.item

        return { [weak self] item, params, neighbors in
            let themeUpdated = currentItem?.theme !== item.theme
            let separatorHeight = UIScreenPixel
            let contentSize = CGSize(width: params.width, height: 74.0)
            let insets = itemListNeighborsGroupedInsets(neighbors, params)
            let layout = ListViewItemNodeLayout(contentSize: contentSize, insets: insets)
            let layoutSize = layout.size

            return (layout, { [weak self] in
                guard let self else {
                    return
                }
                let firstTime = self.item == nil
                self.item = item
                self.layoutParams = params

                self.backgroundNode.backgroundColor = item.theme.list.itemBlocksBackgroundColor
                self.topStripeNode.backgroundColor = item.theme.list.itemBlocksSeparatorColor
                self.bottomStripeNode.backgroundColor = item.theme.list.itemBlocksSeparatorColor

                if self.backgroundNode.supernode == nil {
                    self.insertSubnode(self.backgroundNode, at: 0)
                }
                if self.topStripeNode.supernode == nil {
                    self.insertSubnode(self.topStripeNode, at: 1)
                }
                if self.bottomStripeNode.supernode == nil {
                    self.insertSubnode(self.bottomStripeNode, at: 2)
                }
                if self.maskNode.supernode == nil {
                    self.insertSubnode(self.maskNode, at: 3)
                }

                let hasCorners = itemListHasRoundedBlockLayout(params)
                var hasTopCorners = false
                var hasBottomCorners = false
                switch neighbors.top {
                case .sameSection(false):
                    self.topStripeNode.isHidden = true
                default:
                    hasTopCorners = true
                    self.topStripeNode.isHidden = hasCorners
                }
                let bottomStripeInset: CGFloat
                let bottomStripeOffset: CGFloat
                switch neighbors.bottom {
                case .sameSection(false):
                    bottomStripeInset = params.leftInset + 16.0
                    bottomStripeOffset = -separatorHeight
                    self.bottomStripeNode.isHidden = false
                default:
                    bottomStripeInset = 0.0
                    bottomStripeOffset = 0.0
                    hasBottomCorners = true
                    self.bottomStripeNode.isHidden = hasCorners
                }

                self.maskNode.image = hasCorners ? PresentationResourcesItemList.cornersImage(item.theme, top: hasTopCorners, bottom: hasBottomCorners) : nil
                self.backgroundNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: contentSize.height + min(insets.top, separatorHeight) + min(insets.bottom, separatorHeight)))
                self.maskNode.frame = self.backgroundNode.frame.inset(by: UIEdgeInsets(top: 0.0, left: params.leftInset, bottom: 0.0, right: params.rightInset))
                self.topStripeNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: layoutSize.width, height: separatorHeight))
                self.bottomStripeNode.frame = CGRect(origin: CGPoint(x: bottomStripeInset, y: contentSize.height + bottomStripeOffset), size: CGSize(width: layoutSize.width - bottomStripeInset, height: separatorHeight))

                let font = Font.regular(13.0)
                self.leftTextNode.attributedText = NSAttributedString(string: item.leftTitle, font: font, textColor: item.theme.list.itemSecondaryTextColor)
                self.rightTextNode.attributedText = NSAttributedString(string: item.rightTitle, font: font, textColor: item.theme.list.itemSecondaryTextColor)
                let textWidth = (params.width - params.leftInset - params.rightInset) * 0.5 - 20.0
                let leftSize = self.leftTextNode.updateLayout(CGSize(width: textWidth, height: 20.0))
                let rightSize = self.rightTextNode.updateLayout(CGSize(width: textWidth, height: 20.0))
                self.leftTextNode.frame = CGRect(origin: CGPoint(x: params.leftInset + 18.0, y: 48.0), size: leftSize)
                self.rightTextNode.frame = CGRect(origin: CGPoint(x: params.width - params.rightInset - 18.0 - rightSize.width, y: 48.0), size: rightSize)

                if let sliderView = self.sliderView {
                    self.configure(sliderView: sliderView, item: item, params: params, setValue: firstTime, themeUpdated: themeUpdated)
                }
            })
        }
    }

    override func animateInsertion(_ currentTimestamp: Double, duration: Double, options: ListViewItemAnimationOptions) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.4)
    }

    override func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false)
    }

    @objc private func sliderValueChanged() {
        guard let sliderView = self.sliderView, let item = self.item else {
            return
        }
        let value = Int(sliderView.value.rounded())
        item.updated(max(0, min(item.positions - 1, value)))
    }
}
