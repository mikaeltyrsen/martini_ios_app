//
//  Uiplayground.swift
//  Martini
//
//  Created by Mikael Tyrsen on 11/29/25.
//

import SwiftUI

struct Uiplayground: View {
    var body: some View {
        NavigationStack {
            Text("Hello, World!")
                .navigationTitle("UI Playground")
        }
        
        .toolbar {
            // Bottom 3-button toolbar (left-aligned, intrinsic width)
            ToolbarItem(placement: .bottomBar) {
                Button {
                    // TODO: Home action
                } label: {
                    Label("Home", systemImage: "house")
                }
            }
            ToolbarItem(placement: .bottomBar) {
                Button {
                    // TODO: Search action
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
            }
            ToolbarItem(placement: .bottomBar) {
                Button {
                    // TODO: Profile action
                } label: {
                    Label("Profile", systemImage: "person.crop.circle")
                }
            }
        }
    }
}

#Preview {
    Uiplayground()
}
