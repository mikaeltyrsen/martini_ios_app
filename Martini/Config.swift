import SwiftUI

enum AppConfig {
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
    static let martiniBlue = Color("MartiniBlue")
    static let martiniCyan = Color("MartiniCyan")
    static let martiniGray = Color("MartiniGray")
    static let martiniGreen = Color("MartiniGreen")
    static let martiniLime = Color("MartiniLime")
    static let martiniOrange = Color("MartiniOrange")
    static let martiniPink = Color("MartiniPink")
    static let martiniPurple = Color("MartiniPurple")
    static let martiniRed = Color("MartiniRed")
    static let martiniYellow = Color("MartiniYellow")
}
