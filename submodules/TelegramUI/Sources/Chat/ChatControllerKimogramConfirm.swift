import Foundation
import UIKit
import Display
import TelegramCore
import AccountContext
import PresentationDataUtils

extension ChatControllerImpl {
    /// Kimogram: asks before a sticker or GIF goes out, so a stray tap in the panel sends nothing,
    /// then runs the usual paid-message check.
    func kimogramConfirmStickerThenPresentPaidMessageAlertIfNeeded(isGif: Bool, completion: @escaping (Bool) -> Void) {
        guard KimogramSettings.get(.confirmStickers) else {
            self.presentPaidMessageAlertIfNeeded(completion: completion)
            return
        }
        let presentationData = self.presentationData
        let ru = presentationData.strings.baseLanguageCode == "ru"
        let text: String
        if isGif {
            text = ru ? "Отправить GIF?" : "Send this GIF?"
        } else {
            text = ru ? "Отправить стикер?" : "Send this sticker?"
        }
        self.present(textAlertController(context: self.context, title: nil, text: text, actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .defaultAction, title: ru ? "Отправить" : "Send", action: { [weak self] in
                self?.presentPaidMessageAlertIfNeeded(completion: completion)
            })
        ]), in: .window(.root))
    }

    /// Kimogram: asks "Send this message?" before the composer's message goes out.
    func kimogramConfirmSendIfNeeded(isEditing: Bool, completion: @escaping () -> Void) {
        guard KimogramSettings.get(.confirmSend), !isEditing else {
            completion()
            return
        }
        let presentationData = self.presentationData
        let ru = presentationData.strings.baseLanguageCode == "ru"
        self.present(textAlertController(context: self.context, title: nil, text: ru ? "Отправить сообщение?" : "Send this message?", actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .defaultAction, title: ru ? "Отправить" : "Send", action: {
                completion()
            })
        ]), in: .window(.root))
    }
}
