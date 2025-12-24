import SwiftUI

enum AppConfig {
    enum MarkerIcons {
        static let done = "checkmark.circle"
        static let here = "figure.wave"
        static let next = "arrow.turn.up.right"
        static let omit = "minus.circle.dashed"
        static let none = "xmark.circle"

        static func systemImageName(for status: FrameStatus) -> String {
            switch status {
            case .done:
                return done
            case .here:
                return here
            case .next:
                return next
            case .omit:
                return omit
            case .none:
                return none
            }
        }
    }
}

extension Color {
    static let martiniDefaultColor = Color("MartiniDefaultColor")
}
