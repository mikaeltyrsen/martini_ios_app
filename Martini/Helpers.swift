import Foundation

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
