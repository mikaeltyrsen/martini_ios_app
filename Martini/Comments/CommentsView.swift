import SwiftUI

struct CommentsView: View {
    let frameTitle: String
    @Binding var comments: [Comment]
    let isLoading: Bool
    let errorMessage: String?
    @Binding var isVisible: Bool
    let onReload: () async -> Void
    @State private var newCommentText: String = ""
    @FocusState private var composeFieldFocused: Bool
    @EnvironmentObject private var authService: AuthService

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
                            CommentThreadView(comment: comment, onToggleStatus: toggleStatus)
                                .padding(.bottom, 4)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    .padding(.bottom, 24)
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: comments)
            }
        }
        .navigationTitle("Comments for \(frameTitle)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await onReload()
        }
        .onAppear {
            isVisible = true
        }
        .onDisappear {
            isVisible = false
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

    private func toggleStatus(for comment: Comment) {
        let currentStatus = comment.statusValue ?? 0
        let newStatus = currentStatus == 1 ? 0 : 1
        Task {
            await updateCommentStatus(commentId: comment.id, status: newStatus)
        }
    }

    @MainActor
    private func updateCommentStatus(commentId: String, status: Int) async {
        do {
            try await authService.updateCommentStatus(commentId: commentId, status: status)
            comments = updatedComments(comments, commentId: commentId, status: status)
        } catch {
            print("❌ Failed to update comment status: \(error.localizedDescription)")
        }
    }

    private func updatedComments(_ comments: [Comment], commentId: String, status: Int) -> [Comment] {
        comments.map { comment in
            if comment.id == commentId {
                return comment.updatingStatus(status)
            }

            let updatedReplies = updatedComments(comment.replies, commentId: commentId, status: status)
            if updatedReplies != comment.replies {
                return comment.updatingReplies(updatedReplies)
            }

            return comment
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
    let frameTitle: String

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
                            Text("This is a placeholder comment for \(frameTitle). It can wrap across multiple lines to demonstrate scrolling.")
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
    let onToggleStatus: (Comment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CommentLayout(comment: comment, isReply: false, onToggleStatus: onToggleStatus)

            if !comment.replies.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(comment.replies) { reply in
                        CommentLayout(comment: reply, isReply: true, onToggleStatus: onToggleStatus)
                    }
                }
                .padding(.leading, 24)
            }
        }
    }
}
