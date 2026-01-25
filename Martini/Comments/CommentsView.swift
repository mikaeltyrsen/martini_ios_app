import SwiftUI
import UIKit

struct CommentsView: View {
    let frameTitle: String
    let frameId: String?
    let creativeId: String
    @Binding var comments: [Comment]
    let isLoading: Bool
    let errorMessage: String?
    @Binding var isVisible: Bool
    let onReload: () async -> Void
    @State private var newCommentText: String = ""
    @FocusState private var composeFieldFocused: Bool
    @EnvironmentObject private var authService: AuthService
    @AppStorage("guestName") private var guestName: String = ""
    @State private var keyboardHeight: CGFloat = 0
    @State private var isSendingComment = false
    @State private var sendErrorMessage: String?
    @State private var replyMentionUserId: String?
    @State private var replyMentionName: String?
    @State private var replyToCommentId: String?
    private let bottomAnchorId = "comments-bottom-anchor"
    private var allowsComposing: Bool { frameId != nil && authService.allowEdit }

    var body: some View {
        ZStack(alignment: .bottom) {
            commentsContent
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        toolbarContent
                    }
                }
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
                bottomInsetContent
            }
            //.background(Color.clear)
            .alert("Unable to post comment", isPresented: hasSendErrorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(sendErrorMessage ?? "Please try again.")
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
                    return
                }
                keyboardHeight = frame.height
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardHeight = 0
            }
        }
    }

    @ViewBuilder
    private var commentsContent: some View {
        if comments.isEmpty {
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
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(comments) { comment in
                            CommentThreadView(
                                comment: comment,
                                onToggleStatus: toggleStatus,
                                onReply: handleReply,
                                onCopyComment: copyComment
                            )
                            .padding(.bottom, 4)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchorId)
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    .padding(.bottom, 24)
                }
                .coordinateSpace(name: "comments-scroll")
                .onAppear {
                    DispatchQueue.main.async {
                        scrollToBottom(using: proxy, animated: false)
                    }
                }
                .onChange(of: totalCommentCount(in: comments)) { _ in
                    DispatchQueue.main.async {
                        scrollToBottom(using: proxy, animated: true)
                    }
                }
                .onChange(of: keyboardHeight) { height in
                    if height > 0 {
                        DispatchQueue.main.async {
                            scrollToBottom(using: proxy, animated: true)
                        }
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: comments)
            }
        }
    }

    private var toolbarContent: some View {
        HStack(spacing: 8) {
            if isLoading {
                ProgressView()
            }
            Text(navigationTitle)
                .font(.headline)
        }
    }

    private var bottomInsetContent: some View {
        VStack(spacing: 0) {
            if allowsComposing {
                commentComposer
            } else {
                commentAccessNote
            }
        }
        .padding(.horizontal)
        .padding(.top, 6)
        .background {
            // Background for the inset area
            LinearGradient(
                colors: [
                    Color(uiColor: .systemBackground).opacity(1.0), // bottom
                    Color(uiColor: .systemBackground).opacity(0.0)  // top
                ],
                startPoint: .bottom,
                endPoint: .top
            )
            .ignoresSafeArea(edges: .bottom) // make sure it fills the home-indicator area
        }
    }

    private func sendComment() {
        let trimmed = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = guestName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSendingComment else { return }
        guard !name.isEmpty else {
            sendErrorMessage = "Please add your name in Settings before posting a comment."
            return
        }
        guard let projectId = authService.projectId else {
            sendErrorMessage = "Missing project information."
            return
        }
        guard let frameId else {
            sendErrorMessage = "Select a frame to add a comment."
            return
        }

        isSendingComment = true
        let resolvedComment = resolvedCommentBody(from: trimmed)
        Task {
            do {
                let commentId = try await authService.addComment(
                    projectId: projectId,
                    creativeId: creativeId,
                    frameId: frameId,
                    comment: resolvedComment,
                    guestName: name,
                    commentId: replyToCommentId
                )
                let newComment = Comment(
                    id: commentId,
                    guestName: name,
                    comment: resolvedComment,
                    frameId: frameId
                )
                await MainActor.run {
                    withAnimation(.default) {
                        if let replyToCommentId {
                            comments = insertingReply(into: comments, replyToId: replyToCommentId, reply: newComment)
                        } else {
                            comments.append(newComment)
                        }
                        newCommentText = ""
                        composeFieldFocused = false
                        replyMentionUserId = nil
                        replyMentionName = nil
                        replyToCommentId = nil
                    }
                }
            } catch {
                await MainActor.run {
                    sendErrorMessage = error.localizedDescription
                }
            }
            await MainActor.run {
                isSendingComment = false
            }
        }
    }

    private func toggleStatus(for comment: Comment) {
        let currentStatus = comment.statusValue ?? 0
        let newStatus = currentStatus == 2 ? 0 : 2
        Task {
            await updateCommentStatus(commentId: comment.id, status: newStatus)
        }
    }

    private func handleReply(to comment: Comment) {
        let name = displayName(for: comment)
        newCommentText = "@\(name) "
        replyMentionUserId = comment.userId
        replyMentionName = name
        replyToCommentId = comment.id
        composeFieldFocused = true
    }

    private func copyComment(_ comment: Comment) {
        UIPasteboard.general.string = comment.comment ?? ""
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

    private func insertingReply(into comments: [Comment], replyToId: String, reply: Comment) -> [Comment] {
        comments.map { comment in
            if comment.id == replyToId {
                return comment.updatingReplies(comment.replies + [reply])
            }

            let updatedReplies = insertingReply(into: comment.replies, replyToId: replyToId, reply: reply)
            if updatedReplies != comment.replies {
                return comment.updatingReplies(updatedReplies)
            }

            return comment
        }
    }

    private var commentComposer: some View {
        HStack(spacing: 8) {
            TextField("Add Comment", text: $newCommentText)
                .focused($composeFieldFocused)
                .submitLabel(.send)
                .onTapGesture { composeFieldFocused = true }
                .onSubmit(sendComment)
                .onChange(of: newCommentText) { newValue in
                    guard let mentionName = replyMentionName else { return }
                    let prefix = "@\(mentionName)"
                    if !newValue.hasPrefix(prefix) {
                        replyMentionUserId = nil
                        replyMentionName = nil
                        replyToCommentId = nil
                    }
                }
                .foregroundStyle(.primary)
                .textFieldStyle(.plain)
                .tint(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
        }
        .glassEffect()
    }

    private var commentAccessNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text("Select a frame to add a comment.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func displayName(for comment: Comment) -> String {
        comment.name ?? comment.guestName ?? "Unknown"
    }

    private func resolvedCommentBody(from body: String) -> String {
        guard let mentionUserId = replyMentionUserId,
              let mentionName = replyMentionName,
              !mentionUserId.isEmpty
        else {
            return body
        }

        let mentionPrefix = "@\(mentionName)"
        guard body.hasPrefix(mentionPrefix) else { return body }

        let remainder = body.dropFirst(mentionPrefix.count)
        let trimmedRemainder = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        let mentionSpan = "<span class=\"mention\" contenteditable=\"false\" data-user-id=\"\(mentionUserId)\">@\(mentionName)</span>&nbsp;"

        if trimmedRemainder.isEmpty {
            return mentionSpan
        }

        return mentionSpan + trimmedRemainder
    }

    private var navigationTitle: String {
        if isLoading {
            return "Loading comments"
        }
        if frameTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Comments"
        }
        return "Comments for \(frameTitle)"
    }

    private func scrollToBottom(using proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(bottomAnchorId, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(bottomAnchorId, anchor: .bottom)
        }
    }

    private func totalCommentCount(in comments: [Comment]) -> Int {
        comments.reduce(0) { partial, comment in
            partial + 1 + totalCommentCount(in: comment.replies)
        }
    }

    private var hasSendErrorBinding: Binding<Bool> {
        Binding(
            get: { sendErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    sendErrorMessage = nil
                }
            }
        )
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
                        TextField("Comment", text: $newCommentText)
                            .focused($composeFieldFocused)
                            .submitLabel(.send)
                            .onTapGesture { composeFieldFocused = true }
                            .onSubmit(sendComment)
                            .foregroundStyle(.primary)
                            .textFieldStyle(.plain)
                            .tint(.primary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 10)
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
    let onReply: (Comment) -> Void
    let onCopyComment: (Comment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CommentRow(comment: comment, isReply: false, onToggleStatus: onToggleStatus)

            if !comment.replies.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(comment.replies) { reply in
                        CommentRow(comment: reply, isReply: true, onToggleStatus: onToggleStatus)
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.commentBackground.opacity(1))
        )
        .contextMenu {
            Button("Reply to comment") {
                onReply(comment)
            }
            Button(commentStatusLabel(for: comment)) {
                onToggleStatus(comment)
            }
            Button("Copy comment") {
                onCopyComment(comment)
            }
        }
    }

    private func commentStatusLabel(for comment: Comment) -> String {
        (comment.statusValue ?? 0) == 2 ? "Mark as undone" : "Mark as done"
    }
}
