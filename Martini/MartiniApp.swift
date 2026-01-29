//
//  MartiniApp.swift
//  Martini
//
//  Created by Mikael Tyrsen on 11/15/25.
//

import Foundation
import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .all
    private let pushNotificationManager = PushNotificationManager.shared

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        Self.orientationLock
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        pushNotificationManager.configure()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        pushNotificationManager.updateDeviceToken(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        pushNotificationManager.handleRegistrationFailure(error)
    }
}

@main
struct MartiniApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("themePreference") private var themePreferenceRawValue = ThemePreference.system.rawValue
    @StateObject private var authService: AuthService
    @StateObject private var realtimeService: RealtimeService
    @StateObject private var connectionMonitor: ConnectionMonitor
    @StateObject private var fullscreenCoordinator = FullscreenMediaCoordinator()
    @StateObject private var nearbySignInService = NearbySignInService()

    init() {
        let connectionMonitor = ConnectionMonitor(
            pingURLProvider: { AppEnvironment.pingURL }
        )
        _connectionMonitor = StateObject(wrappedValue: connectionMonitor)
        let authService = AuthService(connectionMonitor: connectionMonitor)
        _authService = StateObject(wrappedValue: authService)
        _realtimeService = StateObject(wrappedValue: RealtimeService(authService: authService))
    }
    
    var body: some Scene {
        WindowGroup {
            if let colorScheme = themePreference.colorScheme {
                configuredContentView
                    .preferredColorScheme(colorScheme)
            } else {
                configuredContentView
            }
        }
    }

    private var configuredContentView: some View {
        ContentView()
            .environmentObject(authService)
            .environmentObject(realtimeService)
            .environmentObject(connectionMonitor)
            .environmentObject(fullscreenCoordinator)
            .environmentObject(nearbySignInService)
            .fullscreenMediaCoordinator(fullscreenCoordinator)
            //.tint(.martiniDefaultColor)
            .accentColor(.martiniDefaultColor)
    }

    private var themePreference: ThemePreference {
        ThemePreference(rawValue: themePreferenceRawValue) ?? .system
    }
}
