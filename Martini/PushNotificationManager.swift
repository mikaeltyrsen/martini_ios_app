//
//  PushNotificationManager.swift
//  Martini
//
//  Created by OpenAI on 2025-01-01.
//

import Foundation
import UIKit
import UserNotifications

extension Notification.Name {
    static let didRegisterForPushNotifications = Notification.Name("martini.didRegisterForPushNotifications")
    static let didReceivePushNotification = Notification.Name("martini.didReceivePushNotification")
}

final class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var deviceToken: String?

    private let deviceTokenKey = "martini_apns_device_token"
    private let notificationCenter = UNUserNotificationCenter.current()

    func configure() {
        notificationCenter.delegate = self
        notificationCenter.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.authorizationStatus = settings.authorizationStatus
            }

            switch settings.authorizationStatus {
            case .notDetermined:
                self?.requestAuthorization()
            case .authorized, .provisional, .ephemeral:
                self?.registerForRemoteNotifications()
            case .denied:
                break
            @unknown default:
                break
            }
        }

        if let cachedToken = UserDefaults.standard.string(forKey: deviceTokenKey) {
            deviceToken = cachedToken
        }
    }

    func requestAuthorization() {
        notificationCenter.requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, error in
            if let error {
                print("❌ Push authorization failed: \(error.localizedDescription)")
            }

            DispatchQueue.main.async {
                self?.authorizationStatus = granted ? .authorized : .denied
            }

            if granted {
                self?.registerForRemoteNotifications()
            }
        }
    }

    func registerForRemoteNotifications() {
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func updateDeviceToken(_ tokenData: Data) {
        let token = tokenData.map { String(format: "%02.2hhx", $0) }.joined()
        UserDefaults.standard.set(token, forKey: deviceTokenKey)
        DispatchQueue.main.async { [weak self] in
            self?.deviceToken = token
        }
        NotificationCenter.default.post(name: .didRegisterForPushNotifications, object: token)
        print("✅ APNS device token registered: \(token)")
    }

    func handleRegistrationFailure(_ error: Error) {
        print("❌ Failed to register for remote notifications: \(error.localizedDescription)")
    }
}

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        NotificationCenter.default.post(
            name: .didReceivePushNotification,
            object: notification.request.content.userInfo
        )
        completionHandler([.banner, .list, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        NotificationCenter.default.post(
            name: .didReceivePushNotification,
            object: response.notification.request.content.userInfo
        )
        completionHandler()
    }
}
