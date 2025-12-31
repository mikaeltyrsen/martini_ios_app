import Foundation
import UIKit

/// Formats a date string from `yyyy-MM-dd` into a user-friendly style.
/// - Parameters:
///   - dateString: The input date string, expected in `yyyy-MM-dd` format.
///   - includeYear: When `true`, the returned value will include the year (e.g., "Dec 11, 2025").
/// - Returns: A formatted date string, or the original input if parsing fails.
public func formattedScheduleDate(from dateString: String, includeYear: Bool = true) -> String {
    let inputFormatter = DateFormatter()
    inputFormatter.locale = Locale(identifier: "en_US_POSIX")
    inputFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    inputFormatter.dateFormat = "yyyy-MM-dd"

    guard let date = inputFormatter.date(from: dateString) else {
        return dateString
    }

    let outputFormatter = DateFormatter()
    outputFormatter.locale = .current
    outputFormatter.timeZone = .current
    outputFormatter.dateFormat = includeYear ? "MMM d, yyyy" : "MMM d"

    return outputFormatter.string(from: date)
}

/// Converts a 24-hour time string (e.g., "18:30") to a 12-hour clock (e.g., "6:30 PM").
/// - Parameter timeString: The input time string, expected in `HH:mm` format.
/// - Returns: A formatted time string, or the original input if parsing fails.
public func formattedTimeFrom24Hour(_ timeString: String) -> String {
    let inputFormatter = DateFormatter()
    inputFormatter.locale = Locale(identifier: "en_US_POSIX")
    inputFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    inputFormatter.dateFormat = "HH:mm"

    guard let date = inputFormatter.date(from: timeString) else {
        return timeString
    }

    let outputFormatter = DateFormatter()
    outputFormatter.locale = .current
    outputFormatter.timeZone = .current
    outputFormatter.dateFormat = "h:mm a"

    return outputFormatter.string(from: date)
}

public func attributedStringFromHTML(
    _ html: String,
    defaultColor: UIColor? = nil,
    baseFontSize: CGFloat? = nil
) -> AttributedString? {
    let resolvedTraits = UITraitCollection.current
    let resolvedDefaultColor = defaultColor?.resolvedColor(with: resolvedTraits)
    let colorKey = resolvedDefaultColor.map(rgbaCacheKey) ?? "nil"
    let fontSizeKey = baseFontSize.map { String(format: "%.2f", $0) } ?? "preferred"
    let cacheKey = "\(resolvedTraits.userInterfaceStyle.rawValue)|\(fontSizeKey)|\(colorKey)|\(html)" as NSString

    if let cached = HTMLAttributedStringCache.shared.value(forKey: cacheKey) {
        return cached
    }

    let preferredFont = UIFont.preferredFont(forTextStyle: .body)
    let resolvedFontSize = baseFontSize ?? preferredFont.pointSize
    let baseFont = preferredFont.withSize(resolvedFontSize)
    let fontSize = "\(resolvedFontSize)px"
    let sanitizedHTML = html.replacingOccurrences(of: "\u{0000}", with: "")
    let styledHTML = """
    <html>
    <head>
    <style>
    body { font-family: -apple-system; font-size: \(fontSize); }
    p { margin: 0 0 1em 0; }
    p:last-child { margin-bottom: 0; }
    .ql-align-center { text-align: center; }
    .ql-align-left { text-align: left; }
    .ql-align-right { text-align: right; }
    </style>
    </head>
    <body>
    \(sanitizedHTML)
    </body>
    </html>
    """

    guard let data = styledHTML.data(using: .utf8, allowLossyConversion: true) else {
        return nil
    }

    let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
        .documentType: NSAttributedString.DocumentType.html,
        .characterEncoding: String.Encoding.utf8.rawValue
    ]

    guard let attributed = try? NSMutableAttributedString(data: data, options: options, documentAttributes: nil) else {
        return nil
    }

    let fullRange = NSRange(location: 0, length: attributed.length)
    attributed.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
        if let font = value as? UIFont,
           let descriptor = baseFont.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits) {
            attributed.addAttribute(.font, value: UIFont(descriptor: descriptor, size: baseFont.pointSize), range: range)
        } else {
            attributed.addAttribute(.font, value: baseFont, range: range)
        }
    }

    let fallbackColor = adjustedReadableTextColor(resolvedDefaultColor ?? dynamicReadableTextColor())
        .resolvedColor(with: resolvedTraits)
    attributed.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, range, _ in
        if let color = value as? UIColor {
            let adjustedColor = adjustedReadableTextColor(color)
                .resolvedColor(with: resolvedTraits)
            if adjustedColor != color {
                attributed.addAttribute(.foregroundColor, value: adjustedColor, range: range)
            }
        } else {
            attributed.addAttribute(.foregroundColor, value: fallbackColor, range: range)
        }
    }

    let attributedString = AttributedString(attributed)
    HTMLAttributedStringCache.shared.insert(attributedString, forKey: cacheKey)
    return attributedString
}

private func dynamicReadableTextColor() -> UIColor {
    UIColor { trait in
        trait.userInterfaceStyle == .dark ? .white : .black
    }
}

private func adjustedReadableTextColor(_ color: UIColor) -> UIColor {
    guard isPureBlackOrWhite(color) else {
        return color
    }

    return dynamicReadableTextColor()
}

private func isPureBlackOrWhite(_ color: UIColor) -> Bool {
    let resolvedColor = color.resolvedColor(with: UITraitCollection.current)
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0

    if resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
        let epsilon: CGFloat = 0.001
        let isBlack = red <= epsilon && green <= epsilon && blue <= epsilon
        let isWhite = red >= 1 - epsilon && green >= 1 - epsilon && blue >= 1 - epsilon
        return isBlack || isWhite
    }

    var white: CGFloat = 0
    if resolvedColor.getWhite(&white, alpha: &alpha) {
        let epsilon: CGFloat = 0.001
        return white <= epsilon || white >= 1 - epsilon
    }

    return false
}

private final class HTMLAttributedStringCache {
    static let shared = HTMLAttributedStringCache()

    private let cache = NSCache<NSString, AttributedStringBox>()

    private init() {}

    func value(forKey key: NSString) -> AttributedString? {
        cache.object(forKey: key)?.value
    }

    func insert(_ value: AttributedString, forKey key: NSString) {
        cache.setObject(AttributedStringBox(value), forKey: key)
    }
}

private final class AttributedStringBox: NSObject {
    let value: AttributedString

    init(_ value: AttributedString) {
        self.value = value
    }
}

private func rgbaCacheKey(for color: UIColor) -> String {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    if color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
        return String(format: "%.4f-%.4f-%.4f-%.4f", red, green, blue, alpha)
    }

    var white: CGFloat = 0
    if color.getWhite(&white, alpha: &alpha) {
        return String(format: "w%.4f-%.4f", white, alpha)
    }

    return color.description
}

/// Converts a simple HTML string to plain text by removing tags,
/// translating common line breaks to newlines, decoding common entities,
/// and collapsing excessive whitespace.
public func plainTextFromHTML(_ html: String) -> String {
    var text = html
    // Replace common line break tags with newlines
    text = text.replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
    text = text.replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
    text = text.replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
    text = text.replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)

    // Strip remaining tags via regex
    if let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
        let range = NSRange(location: 0, length: (text as NSString).length)
        text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    // Decode a few common HTML entities
    let entities: [String: String] = [
        "&amp;": "&",
        "&lt;": "<",
        "&gt;": ">",
        "&quot;": "\"",
        "&#39;": "'"
    ]
    for (entity, value) in entities {
        text = text.replacingOccurrences(of: entity, with: value)
    }

    // Collapse excessive whitespace
    let components = text.components(separatedBy: .whitespacesAndNewlines)
    let collapsed = components.filter { !$0.isEmpty }.joined(separator: " ")
    return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
}

struct ProgressCounts {
    let completed: Int
    let total: Int

    var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
}

func progressCounts(
    for frames: [Frame],
    totalOverride: Int? = nil,
    completedStatuses: Set<FrameStatus> = [.done, .omit]
) -> ProgressCounts {
    let completed = frames.filter { completedStatuses.contains($0.statusEnum) }.count
    let total = totalOverride ?? frames.count

    return ProgressCounts(completed: min(completed, total), total: total)
}

/// Formats a duration in minutes into a combination of hours and minutes.
/// - Parameter minutes: The duration in minutes.
/// - Returns: A human-readable string such as "45min" or "1h 30min".
public func formattedDuration(fromMinutes minutes: Int) -> String {
    let hours = minutes / 60
    let remainingMinutes = minutes % 60

    if hours > 0 && remainingMinutes > 0 {
        return "\(hours)h \(remainingMinutes)min"
    } else if hours > 0 {
        return "\(hours)h"
    } else {
        return "\(minutes)min"
    }
}

func triggerStatusHaptic(for status: FrameStatus) {
    switch status {
    case .done:
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    case .omit:
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)
    default:
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.prepare()
        impact.impactOccurred(intensity: 0.9)
    }
}
