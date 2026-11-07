import Foundation
import UIKit
import Display
import AsyncDisplayKit
import TelegramPresentationData

/// Kimogram: what the long-press preview of a locked chat shows instead of its messages.
final class KimogramLockedChatPreviewController: ViewController {
    private let presentationData: PresentationData

    init(presentationData: PresentationData) {
        self.presentationData = presentationData
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadDisplayNode() {
        self.displayNode = KimogramLockedChatPreviewNode(presentationData: self.presentationData)
        self.displayNodeDidLoad()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        (self.displayNode as? KimogramLockedChatPreviewNode)?.updateLayout(size: layout.size)
    }
}

private final class KimogramLockedChatPreviewNode: ASDisplayNode {
    private let iconNode: ASImageNode
    private let textNode: ImmediateTextNode

    init(presentationData: PresentationData) {
        self.iconNode = ASImageNode()
        self.iconNode.displaysAsynchronously = false
        self.iconNode.image = generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Lock"), color: presentationData.theme.list.itemAccentColor)

        self.textNode = ImmediateTextNode()
        self.textNode.displaysAsynchronously = false
        self.textNode.textAlignment = .center
        self.textNode.attributedText = NSAttributedString(string: presentationData.strings.baseLanguageCode == "ru" ? "Чат заблокирован" : "Chat is locked", font: Font.semibold(17.0), textColor: presentationData.theme.list.itemPrimaryTextColor)

        super.init()

        self.backgroundColor = presentationData.theme.list.plainBackgroundColor
        self.addSubnode(self.iconNode)
        self.addSubnode(self.textNode)
    }

    func updateLayout(size: CGSize) {
        let iconSize = CGSize(width: 56.0, height: 56.0)
        let textSize = self.textNode.updateLayout(CGSize(width: size.width - 32.0, height: 40.0))
        let totalHeight = iconSize.height + 12.0 + textSize.height
        let originY = floor((size.height - totalHeight) / 2.0)
        self.iconNode.frame = CGRect(origin: CGPoint(x: floor((size.width - iconSize.width) / 2.0), y: originY), size: iconSize)
        self.textNode.frame = CGRect(origin: CGPoint(x: floor((size.width - textSize.width) / 2.0), y: originY + iconSize.height + 12.0), size: textSize)
    }
}
