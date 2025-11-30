//
//  playground.swift
//  Martini
//
//  Created by Mikael Tyrsen on 11/29/25.
//

import SwiftUI

struct PlaygroundView: View {
    @EnvironmentObject var authService: AuthService

    var body: some View {
        NavigationStack {
            Text("Playground")
                .navigationTitle("Playground")
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Logout") {
                    authService.logout()
                }
                .foregroundColor(.red)
            }
        }
    }
}

#Preview {
    PlaygroundView()
        .environmentObject(AuthService())
}
