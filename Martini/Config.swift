import SwiftUI

enum AppConfig {
    enum MarkerIcons {
        static let done = "xmark"
        static let here = "video"
        static let next = "forward"
        static let omit = "minus"
        static let none = "photo"

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
