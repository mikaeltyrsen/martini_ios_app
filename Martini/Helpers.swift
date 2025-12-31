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
    let fontSize = baseFontSize.map { "\($0)px" } ?? "1em"
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
    \(html)
    </body>
    </html>
    """

    guard let data = styledHTML.data(using: .utf8) else {
        return nil
    }

    let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
        .documentType: NSAttributedString.DocumentType.html,
        .characterEncoding: String.Encoding.utf8.rawValue
    ]

    guard let attributed = try? NSMutableAttributedString(data: data, options: options, documentAttributes: nil) else {
        return nil
    }

    if let defaultColor {
        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, range, _ in
            if value == nil {
                attributed.addAttribute(.foregroundColor, value: defaultColor, range: range)
            }
        }
    }

    return AttributedString(attributed)
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
