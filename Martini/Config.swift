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
    static let martiniAccentColor = Color("MartiniAccentColor")
    static let martiniDefaultDescriptionColor = Color("MartiniDefaultDescriptionColor")
    static let martiniDefaultTextColor = Color("MartiniDefaultTextColor")
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

    static func martiniCreativeColor(from rawValue: String?) -> Color {
        let cleaned = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""

        guard !cleaned.isEmpty else { return .black }

        if let resolved = martiniColorFromHex(cleaned) {
            return resolved
        }

        switch cleaned {
        case "blue":
            return .martiniBlueColor
        case "cyan":
            return .martiniCyanColor
        case "green":
            return .martiniGreenColor
        case "lime":
            return .martiniLimeColor
        case "orange":
            return .martiniOrangeColor
        case "pink":
            return .martiniPinkColor
        case "purple":
            return .martiniPurpleColor
        case "red":
            return .martiniRedColor
        case "yellow":
            return .martiniYellowColor
        default:
            return .martiniDefaultColor
        }
    }

    private static func martiniColorFromHex(_ value: String) -> Color? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else { return nil }

        let hexString = cleaned.hasPrefix("#") ? String(cleaned.dropFirst()) : cleaned
        guard hexString.count == 6 || hexString.count == 8 else { return nil }
        guard hexString.range(of: "^[0-9a-f]+$", options: .regularExpression) != nil else { return nil }

        var hexNumber: UInt64 = 0
        guard Scanner(string: hexString).scanHexInt64(&hexNumber) else { return nil }

        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        if hexString.count == 8 {
            red = Double((hexNumber & 0xFF000000) >> 24) / 255
            green = Double((hexNumber & 0x00FF0000) >> 16) / 255
            blue = Double((hexNumber & 0x0000FF00) >> 8) / 255
            alpha = Double(hexNumber & 0x000000FF) / 255
        } else {
            red = Double((hexNumber & 0xFF0000) >> 16) / 255
            green = Double((hexNumber & 0x00FF00) >> 8) / 255
            blue = Double(hexNumber & 0x0000FF) / 255
            alpha = 1.0
        }

        return Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}
