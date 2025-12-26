import SwiftUI

enum AppConfig {
    static let debugMode = true

    enum MarkerIcons {
        static let done = "xmark"
        static let here = "video.fill"
        static let next = "forward.fill"
        static let omit = "video.slash.fill"
        static let none = "photo.fill"

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
