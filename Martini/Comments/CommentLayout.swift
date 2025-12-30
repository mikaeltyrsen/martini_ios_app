import SwiftUI

struct CommentLayout: View {
    let comment: Comment
    let isReply: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.martiniDefaultColor.opacity(isReply ? 0.12 : 0.2))
                    .frame(width: isReply ? 22 : 28, height: isReply ? 22 : 28)
                Text(displayName)
                    .font(isReply ? .subheadline.weight(.semibold) : .headline)
                Spacer()
                if let lastUpdated = comment.lastUpdated, !lastUpdated.isEmpty {
                    Text(lastUpdated)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let body = comment.comment, !body.isEmpty {
                Text(body)
                    .font(isReply ? .subheadline : .body)
            }

            Divider()
        }
    }

    private var displayName: String {
        comment.name ?? comment.guestName ?? "Unknown"
    }
}

#if DEBUG
struct CommentLayout_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            CommentLayout(comment: sampleComment, isReply: false)
            CommentLayout(comment: sampleReply, isReply: true)
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
