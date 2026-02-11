import SwiftUI
import UIKit

struct CreativeFilterOption: Identifiable, Hashable {
    let id: String
    let creativeId: String?
    let title: String
}

struct CommentsView: View {
    let frameTitle: String
    let frameId: String?
    let creativeId: String?
    let creativeTitle: String?
    let showsCreativeFilter: Bool
    let creativeFilterOptions: [CreativeFilterOption]
    let selectedCreativeFilterId: String?
    let onSelectCreativeFilter: (String?) -> Void
    let onSelectFrame: (String) -> Void
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
    private var allowsComposing: Bool { authService.allowEdit && creativeId != nil }
    private var showsHeader: Bool { frameId == nil }

    var body: some View {
        ZStack(alignment: .bottom) {
            commentsContent
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        toolbarContent
                    }
                    if showsCreativeFilter {
                        ToolbarItem(placement: .topBarTrailing) {
                            creativeFilterMenu
                        }
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
        .overlay(alignment: .top) {
            TopFadeOverlay(color: .martiniAccentColor)
        }
    }

    @ViewBuilder
    private var commentsContent: some View {
        if comments.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text(errorMessage ?? "No comments yet.")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(comments) { comment in
                            CommentThreadView(
                                comment: comment,
                                showFrameBadge: showsHeader,
                                onToggleStatus: toggleStatus,
                                onReply: handleReply,
                                onCopyComment: copyComment,
                                onSelectFrame: onSelectFrame
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
                MartiniLoader()
            }
            VStack(spacing: 2) {
                Text("Comments")
                    .font(.system(size: 20, weight: .semibold))
                if !showsHeader {
                    Text(frameSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var frameSubtitle: String {
        let trimmedTitle = frameTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? "Frame" : trimmedTitle
    }

    private var creativeFilterMenu: some View {
        Menu {
            Button {
                onSelectCreativeFilter(nil)
            } label: {
                if selectedCreativeFilterId == nil {
                    Label("All creatives", systemImage: "checkmark")
                } else {
                    Text("All creatives")
                }
            }

            ForEach(creativeFilterOptions) { option in
                Button {
                    onSelectCreativeFilter(option.creativeId)
                } label: {
                    if option.creativeId == selectedCreativeFilterId {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            Image(systemName: "list.bullet")
                .imageScale(.large)
        }
        .accessibilityLabel("Filter comments by creative")
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
        .padding(.bottom, 8)
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
        guard let creativeId else {
            sendErrorMessage = "Select a creative to add a comment."
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

            // COMMENT FIELD (pill / glass)
            HStack(spacing: 8) {
                if let replyMentionName {
                    replyToken(for: replyMentionName)
                        .padding(.leading, 4)
                }

                TextField("Add Comment", text: $newCommentText)
                    .focused($composeFieldFocused)
                    .submitLabel(.send)
                    .onTapGesture { composeFieldFocused = true }
                    .onSubmit(sendComment)
                    .foregroundStyle(.primary)
                    .textFieldStyle(.plain)
                    .tint(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
            }
            .padding(.horizontal, 8)
            .glassEffect()

            // SEND BUTTON (outside)
            Button(action: sendComment) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(canSendComment ? .white : .secondary)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .background(
                Circle()
                    .fill(canSendComment
                          ? Color.martiniAccentColor
                          : Color.martiniAccentColor.opacity(0))
            )
            .disabled(!canSendComment)
            .glassEffect()
        }
        .padding(.horizontal)
    }

    private func replyToken(for name: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.system(size: 12, weight: .semibold))
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Button {
                clearReplyContext()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.martiniAccentColor.opacity(0.2))
        )
        .accessibilityLabel("Replying to \(name)")
    }

    private var commentAccessNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(commentAccessMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func displayName(for comment: Comment) -> String {
        comment.name ?? comment.guestName ?? "Unknown"
    }

    private func resolvedCommentBody(from body: String) -> String {
        guard let mentionName = replyMentionName,
              !mentionName.isEmpty
        else {
            return body
        }

        let mentionSpan = "<span class=\"mention\">@\(mentionName)</span>&nbsp;"
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedBody.isEmpty {
            return mentionSpan
        }

        return mentionSpan + trimmedBody
    }

    private func clearReplyContext() {
        replyMentionUserId = nil
        replyMentionName = nil
        replyToCommentId = nil
    }

    private var canSendComment: Bool {
        !newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSendingComment
    }

    private var navigationTitle: String {
        if isLoading {
            return "Loading comments"
        }
        if frameId == nil {
            return "Comments"
        }
        if frameTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Comments"
        }
        return "Comments for \(frameTitle)"
    }

    private var commentAccessMessage: String {
        if !authService.allowEdit {
            return "You do not have permission to add comments."
        }
        return "Select a creative to add comments."
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
                        Button(action: sendComment) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(canSendComment ? Color.martiniAccentColor : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSendComment)
                    }
                    .padding(.horizontal, 6)
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

    private var canSendComment: Bool {
        !newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct CommentThreadView: View {
    let comment: Comment
    let showFrameBadge: Bool
    let onToggleStatus: (Comment) -> Void
    let onReply: (Comment) -> Void
    let onCopyComment: (Comment) -> Void
    let onSelectFrame: (String) -> Void
    private let threadPadding: CGFloat = 18
    private let avatarSize: CGFloat = 28
    private let connectorWidth: CGFloat = 4
    private let connectorTrim: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            CommentRow(
                comment: comment,
                isReply: false,
                showFrameBadge: showFrameBadge,
                onToggleStatus: onToggleStatus,
                onSelectFrame: onSelectFrame
            )

            if !comment.replies.isEmpty {
                VStack(alignment: .leading, spacing: 30) {
                    ForEach(comment.replies) { reply in
                        CommentRow(
                            comment: reply,
                            isReply: true,
                            showFrameBadge: showFrameBadge,
                            onToggleStatus: onToggleStatus,
                            onSelectFrame: onSelectFrame
                        )
                    }
                }
            }
        }
        .padding(threadPadding)
        .background {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.commentBackground.opacity(1))

                if !comment.replies.isEmpty {
                    GeometryReader { proxy in
                        let lineHeight = max(0, proxy.size.height - (threadPadding * 2) - avatarSize - connectorTrim)
                        Rectangle()
                            .fill(Color.martiniAccentColor)
                            .frame(width: connectorWidth, height: lineHeight)
                            .offset(
                                x: threadPadding + (avatarSize - connectorWidth) / 2,
                                y: threadPadding + avatarSize / 2
                            )
                    }
                }
            }
        }
        .contextMenu {
            Button {
                onReply(comment)
            } label: {
                Label("Reply to comment", systemImage: "arrowshape.turn.up.left.fill")
            }
            Button {
                onToggleStatus(comment)
            } label: {
                Label(commentStatusLabel(for: comment), systemImage: "checkmark.circle.fill")
            }
            Button {
                onCopyComment(comment)
            } label: {
                Label("Copy comment", systemImage: "document.on.document.fill")
            }
        }
    }

    private func commentStatusLabel(for comment: Comment) -> String {
        (comment.statusValue ?? 0) == 2 ? "Mark as undone" : "Mark as done"
    }
}
