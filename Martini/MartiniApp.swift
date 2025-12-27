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

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        Self.orientationLock
    }
}

@main
struct MartiniApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var authService: AuthService
    @StateObject private var realtimeService: RealtimeService
    @StateObject private var connectionMonitor: ConnectionMonitor
    @StateObject private var fullscreenCoordinator = FullscreenMediaCoordinator()

    init() {
        let connectionMonitor = ConnectionMonitor(
            pingURL: URL(string: "https://dev.staging.trymartini.com/scripts/")!
        )
        _connectionMonitor = StateObject(wrappedValue: connectionMonitor)
        let authService = AuthService(connectionMonitor: connectionMonitor)
        _authService = StateObject(wrappedValue: authService)
        _realtimeService = StateObject(wrappedValue: RealtimeService(authService: authService))
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authService)
                .environmentObject(realtimeService)
                .environmentObject(connectionMonitor)
                .fullscreenMediaCoordinator(fullscreenCoordinator)
                //.tint(.martiniDefaultColor)
                .accentColor(.martiniDefaultColor)
        }
    }
}
