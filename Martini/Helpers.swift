import Foundation

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
