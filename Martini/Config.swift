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
    static let martiniDefaultDescriptionColor = Color("MartiniDefaultDescriptionColor")
    static let martiniBlueColor = Color("MartiniBlue")
    static let martiniBlueBackgroundColor = Color("MartiniBlueBackground")
    static let martiniCyanColor = Color("MartiniCyan")
    static let martiniCyanBackgroundColor = Color("MartiniCyanBackground")
    static let martiniGrayColor = Color("MartiniGray")
    static let martiniGrayBackgroundColor = Color("MartiniGrayBackground")
    static let martiniGreenColor = Color("MartiniGreen")
    static let martiniGreenBackgroundColor = Color("MartiniGreenBackground")
    static let martiniLimeColor = Color("MartiniLime")
    static let martiniLimeBackgroundColor = Color("MartiniLimeBackground")
    static let martiniOrangeColor = Color("MartiniOrange")
    static let martiniOrangeBackgroundColor = Color("MartiniOrangeBackground")
    static let martiniPinkColor = Color("MartiniPink")
    static let martiniPinkBackgroundColor = Color("MartiniPinkBackground")
    static let martiniPurpleColor = Color("MartiniPurple")
    static let martiniPurpleBackgroundColor = Color("MartiniPurpleBackground")
    static let martiniRedColor = Color("MartiniRed")
    static let martiniRedBackgroundColor = Color("MartiniRedBackground")
    static let martiniYellowColor = Color("MartiniYellow")
    static let martiniYellowBackgroundColor = Color("MartiniYellowBackground")
    static let scheduleColor = Color("ScheduleColor")
}
