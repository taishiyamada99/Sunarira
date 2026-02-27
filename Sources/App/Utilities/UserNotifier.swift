import AppKit
import Foundation
import UserNotifications

@MainActor
final class UserNotifier {
    private var hasRequestedAuthorization = false

    func notify(title: String, message: String) {
        Task { [weak self] in
            guard let self else { return }
            await self.requestAuthorizationIfNeeded()

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = message
            content.sound = nil

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )

            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                NSSound.beep()
                AppLogger.warning("Notification delivery failed.")
            }
        }
    }

    private func requestAuthorizationIfNeeded() async {
        guard !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true

        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
        } catch {
            AppLogger.warning("Notification authorization request failed.")
        }
    }
}
