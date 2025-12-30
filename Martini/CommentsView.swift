import SwiftUI

struct CommentsView: View {
    let frameNumber: Int
    let comments: [Comment]
    let isLoading: Bool
    let errorMessage: String?
    let onReload: () async -> Void
    @State private var newCommentText: String = ""
    @FocusState private var composeFieldFocused: Bool

    var body: some View {
        Group {
            if isLoading && comments.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading comments...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if comments.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text(errorMessage ?? "No comments yet.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(comments) { comment in
                            CommentThreadView(comment: comment)
                                .padding(.bottom, 4)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Comments for Frame \(frameNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await onReload()
        }
        .safeAreaInset(edge: .bottom) {
            commentComposer
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
        }
    }

    private func sendComment() {
        let trimmed = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // TODO: Hook into your real comment-posting logic.
        withAnimation(.default) {
            newCommentText = ""
            composeFieldFocused = false
        }
    }

    private var commentComposer: some View {
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "text.bubble")
                    .foregroundStyle(.secondary)
                TextField("Comment", text: $newCommentText)
                    .focused($composeFieldFocused)
                    .submitLabel(.send)
                    .onTapGesture { composeFieldFocused = true }
                    .onSubmit(sendComment)
                    .foregroundStyle(.primary)
            }
            .tint(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.clear, in: Capsule())
            .overlay(
                Capsule().stroke(Color.secondary.opacity(0.22), lineWidth: 1)
            )

            if !newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: sendComment) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct CommentsSheet: View {
    let frameNumber: Int

    @State private var newCommentText: String = ""
    @FocusState private var composeFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(0..<30), id: \.self) { index in
                        let idx: Int = index + 1
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Circle().fill(Color.martiniDefaultColor.opacity(0.2)).frame(width: 28, height: 28)
                                Text("User \(idx)").font(.headline)
                                Spacer()
                                Text("2h ago").font(.caption).foregroundStyle(.secondary)
                            }
                            Text("This is a placeholder comment for frame \(frameNumber). It can wrap across multiple lines to demonstrate scrolling.")
                                .font(.body)
                            Divider()
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        HStack {
                            Image(systemName: "text.bubble")
                                .foregroundStyle(.secondary)
                            TextField("Comment", text: $newCommentText)
                                .focused($composeFieldFocused)
                                .submitLabel(.send)
                                .onTapGesture { composeFieldFocused = true }
                                .onSubmit(sendComment)
                                .foregroundStyle(.primary)
                        }
                        .tint(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.clear, in: Capsule())
                        .overlay(
                            Capsule().stroke(Color.secondary.opacity(0.22), lineWidth: 1)
                        )

                        if !newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button(action: sendComment) {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
        }
    }

    private func sendComment() {
        let trimmed = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // TODO: Hook into your real comment-posting logic.
        withAnimation(.default) {
            newCommentText = ""
            composeFieldFocused = false
        }
    }
}

private struct CommentThreadView: View {
    let comment: Comment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CommentLayout(comment: comment, isReply: false)

            if !comment.replies.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(comment.replies) { reply in
                        CommentLayout(comment: reply, isReply: true)
                    }
                }
                .padding(.leading, 24)
            }
        }
    }
}
