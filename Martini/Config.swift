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
    static let martiniBlueColor = Color("MartiniBlue")
    static let martiniCyanColor = Color("MartiniCyan")
    static let martiniGrayColor = Color("MartiniGray")
    static let martiniGreenColor = Color("MartiniGreen")
    static let martiniLimeColor = Color("MartiniLime")
    static let martiniOrangeColor = Color("MartiniOrange")
    static let martiniPinkColor = Color("MartiniPink")
    static let martiniPurpleColor = Color("MartiniPurple")
    static let martiniRedColor = Color("MartiniRed")
    static let martiniYellowColor = Color("MartiniYellow")
    static let scheduleColor = Color("ScheduleColor")
}
