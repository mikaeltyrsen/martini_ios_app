//
//  ThemePreference.swift
//  Martini
//
//  Created by OpenAI on 3/12/25.
//

import SwiftUI

enum ThemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system:
            return "Follow Device Theme"
        case .light:
            return "Light Mode"
        case .dark:
            return "Dark Mode"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}
