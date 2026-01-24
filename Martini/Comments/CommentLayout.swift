import SwiftUI

struct CommentLayout: View {
    let comment: Comment
    let isReply: Bool
    let onToggleStatus: (Comment) -> Void

    var body: some View {
        CommentRow(comment: comment, isReply: isReply, onToggleStatus: onToggleStatus)
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
    let onToggleStatus: (Comment) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: isReply ? 22 : 28, height: isReply ? 22 : 28)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(displayName)
                        .font(.system(size: 14, weight: .semibold))
                    if let lastUpdated = comment.lastUpdated, !lastUpdated.isEmpty {
                        Text(formattedRelativeTimestamp(from: lastUpdated))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let body = comment.comment, !body.isEmpty {
                    Text(body)
                        .font(isReply ? .subheadline : .body)
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

    private var isStatusComplete: Bool {
        (comment.statusValue ?? 0) == 2
    }

    private var statusColor: Color {
        isStatusComplete ? .green : Color.secondary.opacity(0.25)
    }

    private var statusIconColor: Color {
        isStatusComplete ? .white : .secondary
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
