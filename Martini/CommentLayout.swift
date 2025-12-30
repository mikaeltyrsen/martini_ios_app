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
