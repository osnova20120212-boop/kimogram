import Foundation
import UIKit
import LocalAuthentication
import TelegramCore
import SettingsUI

/// Kimogram: asks for Face ID, Touch ID or the device passcode before a locked chat opens.
///
/// A chat unlocked once stays open until the app goes to the background, so moving between
/// a locked chat and its profile or media does not ask again.
final class KimogramChatLockGate {
    static let shared = KimogramChatLockGate()

    private var unlockedPeerIds = Set<EnginePeer.Id>()
    private var isAuthenticating = false
    private var observer: NSObjectProtocol?

    private init() {
        self.observer = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.unlockedPeerIds.removeAll()
        })
    }

    func unlock(peerId: EnginePeer.Id, completion: @escaping () -> Void) {
        guard KimogramSettings.isChatLocked(peerId), !self.unlockedPeerIds.contains(peerId) else {
            completion()
            return
        }
        if self.isAuthenticating {
            return
        }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode on the device: there is nothing to check against.
            completion()
            return
        }
        self.isAuthenticating = true
        let reason = KimogramAutoProxy.isRussian ? "Откройте заблокированный чат" : "Open the locked chat"
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason, reply: { [weak self] success, _ in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                self.isAuthenticating = false
                if success {
                    self.unlockedPeerIds.insert(peerId)
                    completion()
                }
            }
        })
    }
}
