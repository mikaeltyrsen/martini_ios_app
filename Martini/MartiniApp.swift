//
//  MartiniApp.swift
//  Martini
//
//  Created by Mikael Tyrsen on 11/15/25.
//

import SwiftUI

@main
struct MartiniApp: App {
    @StateObject private var authService: AuthService
    @StateObject private var realtimeService: RealtimeService
    @StateObject private var fullscreenCoordinator = FullscreenMediaCoordinator()

    init() {
        let authService = AuthService()
        _authService = StateObject(wrappedValue: authService)
        _realtimeService = StateObject(wrappedValue: RealtimeService(authService: authService))
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authService)
                .environmentObject(realtimeService)
                .fullscreenMediaCoordinator(fullscreenCoordinator)
        }
    }
}
