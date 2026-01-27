import SwiftUI

struct CommentLayout: View {
    let comment: Comment
    let isReply: Bool
    let onToggleStatus: (Comment) -> Void

    var body: some View {
        CommentRow(
            comment: comment,
            isReply: isReply,
            showFrameBadge: true,
            onToggleStatus: onToggleStatus
        )
            .padding(18) // ⬅️ padding FIRST
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.commentBackground.opacity(1))
        )
    }
}

struct CommentRow: View {
    let comment: Comment
    let isReply: Bool
    let showFrameBadge: Bool
    let onToggleStatus: (Comment) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatarView
                .frame(width: isReply ? 28 : 28, height: isReply ? 28 : 28)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(displayName)
                        .font(.system(size: 14, weight: .semibold))
                    if isGuest {
                        Text("(guest)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    if let lastUpdated = comment.lastUpdated, !lastUpdated.isEmpty {
                        Text(formattedRelativeTimestamp(from: lastUpdated))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if showFrameBadge {
                    if let frameThumbnailURL {
                        frameThumbnailView(url: frameThumbnailURL, badgeText: frameBadgeNumber)
                    } else if let frameBadgeNumber {
                        frameBadgeView(frameBadgeNumber)
                    }
                }

                if let body = comment.comment, !body.isEmpty {
                    Text(attributedComment(from: body))
                }
            }

            Spacer(minLength: 8)

            if isStatusComplete {
                Button {
                    onToggleStatus(comment)
                } label: {
                    ZStack {
                        Circle()
                            .fill(statusColor)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(statusIconColor)
                    }
                }
                .frame(width: isReply ? 22 : 26, height: isReply ? 22 : 26)
                .buttonStyle(.plain)
            }
        }
    }

    private var displayName: String {
        comment.name ?? comment.guestName ?? "Unknown"
    }

    private var isGuest: Bool {
        guard comment.guestName != nil else { return false }
        return (comment.userId ?? "").isEmpty
    }

    private var isStatusComplete: Bool {
        (comment.statusValue ?? 0) == 2
    }

    private var statusColor: Color {
        isStatusComplete ? .green : Color.secondary.opacity(0.25)
    }

    private var statusIconColor: Color {
        isStatusComplete ? .white : .secondary
    }

    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(Color.martiniAccentColor)

            if let avatarUrlString = comment.userAvatar?.trimmingCharacters(in: .whitespacesAndNewlines),
               !avatarUrlString.isEmpty,
               let avatarUrl = URL(string: avatarUrlString) {
                AsyncImage(url: avatarUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        initialsView
                    default:
                        initialsView
                    }
                }
                .clipShape(Circle())
            } else if isGuest {
                Image(systemName: "iphone.smartbatterycase.gen2")
                    .font(.system(size: isReply ? 10 : 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else {
                initialsView
            }
        }
    }

    private var initialsView: some View {
        Text(initials(from: displayName))
            .font(.system(size: isReply ? 10 : 12, weight: .semibold))
            .foregroundStyle(.primary)
    }

    private func initials(from name: String) -> String {
        let components = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .filter { !$0.isEmpty }
        guard let first = components.first else { return "" }
        var initials = String(first.prefix(1))
        if components.count > 1, let last = components.last {
            initials.append(String(last.prefix(1)))
        }
        return String(initials.prefix(2)).uppercased()
    }

    private var frameBadgeNumber: String? {
        guard let frameOrder = comment.frameOrder, frameOrder > 0 else { return nil }
        return String(frameOrder)
    }

    private var frameThumbnailURL: URL? {
        guard let thumb = comment.frameThumb?.trimmingCharacters(in: .whitespacesAndNewlines),
              !thumb.isEmpty
        else {
            return nil
        }
        return URL(string: thumb)
    }

    @ViewBuilder
    private func frameBadgeView(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.8))
            )
    }

    @ViewBuilder
    private func frameThumbnailView(url: URL, badgeText: String?) -> some View {
        ZStack(alignment: .topTrailing) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    frameThumbnailPlaceholder
                default:
                    frameThumbnailPlaceholder
                }
            }
            .frame(width: 152, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(.vertical, 8)

            if let badgeText {
                frameBadgeView(badgeText)
                    .offset(x: 6, y: -6)
            }
        }
    }

    private var frameThumbnailPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.15))
            Image(systemName: "photo")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func attributedComment(from body: String) -> AttributedString {
        let baseFont: Font = isReply ? .subheadline : .subheadline
        var baseAttributes = AttributeContainer()
        baseAttributes.font = baseFont
        baseAttributes.foregroundColor = .primary
        var result = AttributedString()

        let pattern = "<span[^>]*class=\\\"mention\\\"[^>]*>(.*?)</span>\\s*&nbsp;?"
        let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        let nsBody = body as NSString
        var currentLocation = 0

        regex?.enumerateMatches(in: body, options: [], range: NSRange(location: 0, length: nsBody.length)) { match, _, _ in
            guard let match else { return }

            let range = match.range
            if range.location > currentLocation {
                let text = nsBody.substring(with: NSRange(location: currentLocation, length: range.location - currentLocation))
                var attributed = AttributedString(decodedHTMLEntities(text))
                attributed.mergeAttributes(baseAttributes)
                result.append(attributed)
            }

            if match.numberOfRanges > 1, let mentionRange = Range(match.range(at: 1), in: body) {
                let mentionText = decodedHTMLEntities(String(body[mentionRange]))
                var mentionAttributed = AttributedString(mentionText)
                mentionAttributed.font = baseFont.weight(.semibold)
                mentionAttributed.foregroundColor = .martiniAccentColor
                result.append(mentionAttributed)
            }

            currentLocation = range.location + range.length
        }

        if currentLocation < nsBody.length {
            let text = nsBody.substring(with: NSRange(location: currentLocation, length: nsBody.length - currentLocation))
            var attributed = AttributedString(decodedHTMLEntities(text))
            attributed.mergeAttributes(baseAttributes)
            result.append(attributed)
        }

        if result.characters.isEmpty {
            var attributed = AttributedString(decodedHTMLEntities(body))
            attributed.mergeAttributes(baseAttributes)
            return attributed
        }

        return result
    }

    private func decodedHTMLEntities(_ text: String) -> String {
        text.replacingOccurrences(of: "&nbsp;", with: " ")
    }
}

#if DEBUG
struct CommentLayout_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            CommentLayout(comment: sampleComment, isReply: false, onToggleStatus: { _ in })
            CommentLayout(comment: sampleReply, isReply: true, onToggleStatus: { _ in })
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }

    private static var sampleComment: Comment {
        Comment(
            id: "comment-1",
            userId: "user-1",
            guestName: nil,
            comment: "Really like the color grading on this take!",
            marker: nil,
            status: "open",
            frameId: "frame-1",
            frameOrder: 1,
            lastUpdated: "Just now",
            name: "Martini",
            replies: [],
            frameThumb: nil
        )
    }

    private static var sampleReply: Comment {
        Comment(
            id: "reply-1",
            userId: "user-2",
            guestName: nil,
            comment: "Totally agree—maybe lift the shadows a bit more.",
            marker: nil,
            status: "open",
            frameId: "frame-1",
            frameOrder: 1,
            lastUpdated: "2m ago",
            name: "Scout",
            replies: [],
            frameThumb: nil
        )
    }
}
#endif
