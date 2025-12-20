import SwiftUI
import AVKit
import UIKit

@MainActor
struct FrameView: View {
    private let providedFrame: Frame
    @EnvironmentObject private var authService: AuthService
    @State private var frame: Frame
    @Binding var assetOrder: [FrameAssetKind]
    let onClose: () -> Void
    let hasPreviousFrame: Bool
    let hasNextFrame: Bool
    let onNavigate: (FrameNavigationDirection) -> Void
    let onStatusSelected: (Frame, FrameStatus) -> Void
    @State private var selectedStatus: FrameStatus
    @State private var assetStack: [FrameAssetItem]
    @State private var visibleAssetID: FrameAssetItem.ID?
    @State private var showingComments: Bool = false
    @State private var showingFiles: Bool = false
    @State private var clips: [Clip] = []
    @State private var isLoadingClips: Bool = false
    @State private var clipsError: String?
    @State private var filesBadgeCount: Int? = nil
    @State private var descriptionHeightRatio: CGFloat = 0.4
    @State private var dragStartRatio: CGFloat?
    @State private var descriptionScrollOffset: CGFloat = 0
    @State private var isDraggingDescription: Bool = false

    private let minDescriptionRatio: CGFloat = 0.35

    init(
        frame: Frame,
        assetOrder: Binding<[FrameAssetKind]>,
        onClose: @escaping () -> Void,
        hasPreviousFrame: Bool = false,
        hasNextFrame: Bool = false,
        onNavigate: @escaping (FrameNavigationDirection) -> Void = { _ in },
        onStatusSelected: @escaping (Frame, FrameStatus) -> Void = { _, _ in }
    ) {
        providedFrame = frame
        _frame = State(initialValue: frame)
        _assetOrder = assetOrder
        self.onClose = onClose
        self.hasPreviousFrame = hasPreviousFrame
        self.hasNextFrame = hasNextFrame
        self.onNavigate = onNavigate
        self.onStatusSelected = onStatusSelected
        _selectedStatus = State(initialValue: frame.statusEnum)

        let orderValue: [FrameAssetKind] = assetOrder.wrappedValue
        let initialStack: [FrameAssetItem] = FrameView.orderedAssets(for: frame, order: orderValue)
        _assetStack = State(initialValue: initialStack)
        let firstID: FrameAssetItem.ID? = initialStack.first?.id
        _visibleAssetID = State(initialValue: firstID)
    }

    var body: some View {
        NavigationStack {
            contentView
                .navigationTitle("Frame \(frame.frameNumber > 0 ? String(frame.frameNumber) : "")")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    topToolbar
                    bottomToolbar
                }
        }
        .sheet(isPresented: $showingFiles) {
            FilesSheet(
                frame: frame,
                clips: $clips,
                isLoading: $isLoadingClips,
                errorMessage: $clipsError,
                onReload: { await loadClips(force: true) }
            )
            .presentationDetents([.fraction(0.25), .medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: assetOrder) { (newOrder: [FrameAssetKind]) in
            let newStack: [FrameAssetItem] = FrameView.orderedAssets(for: frame, order: newOrder)
            assetStack = newStack
            if visibleAssetID == nil { visibleAssetID = newStack.first?.id }
        }
        .onChange(of: assetStack) { (newStack: [FrameAssetItem]) in
            assetOrder = newStack.map(\.kind)
            if visibleAssetID == nil, let first: FrameAssetItem.ID = newStack.first?.id {
                visibleAssetID = first
            }
        }
        .task {
            await loadClips(force: false)
        }
        .onChange(of: providedFrame.id) { _ in
            syncWithProvidedFrame()
        }
        .onChange(of: authService.frames) { frames in
            guard let updated = frames.first(where: { $0.id == frame.id }) else { return }
            frame = updated
            selectedStatus = updated.statusEnum

            let newStack: [FrameAssetItem] = FrameView.orderedAssets(for: updated, order: assetOrder)
            if assetStack.map(\.id) != newStack.map(\.id) {
                assetStack = newStack
                if visibleAssetID == nil { visibleAssetID = newStack.first?.id }
            }
        }
    }

    @ToolbarContentBuilder
    private var topToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Close") { onClose() }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                onNavigate(.previous)
            } label: {
                Image(systemName: "arrow.up")
            }
            .accessibilityLabel("Previous frame")
            .disabled(!hasPreviousFrame)

            Button {
                onNavigate(.next)
            } label: {
                Image(systemName: "arrow.down")
            }
            .accessibilityLabel("Next frame")
            .disabled(!hasNextFrame)
        }
    }

    @ToolbarContentBuilder
    private var bottomToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            Button {
                showingFiles = true
            } label: {
                Label {
                    Text("Files")
                } icon: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "folder")
                        if let badgeCount = filesBadgeCount, badgeCount > 0 {
                            Text("\(badgeCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(Circle().fill(Color.red))
                                .offset(x: 8, y: -8)
                        }
                    }
                }
            }

            Spacer()

            
            Menu {
                statusMenuButton(title: "Done", status: .done, systemImage: "checkmark.circle")
                statusMenuButton(title: "Here", status: .inProgress, systemImage: "figure.wave")
                statusMenuButton(title: "Next", status: .upNext, systemImage: "arrow.turn.up.right")
                statusMenuButton(title: "Omit", status: .skip, systemImage: "minus.circle")
                if selectedStatus != .none {
                    statusMenuButton(title: "Clear", status: .none, systemImage: "xmark.circle")
                }
            } label: {
                let statusColor = selectedStatus.labelColor
                let statusLabel = selectedStatus == .none ? "Mark Frame" : selectedStatus.displayName
                HStack(spacing: 6) {
                    if selectedStatus != .none {
                        Image(systemName: selectedStatus.systemImageName)
                            .foregroundStyle(statusColor)
                    }
                    Text(statusLabel)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(statusColor)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            Spacer()

            NavigationLink {
                CommentsPage(frameNumber: frame.frameNumber)
            } label: {
                Label("Comments", systemImage: "text.bubble")
            }
            
            
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if assetStack.isEmpty {
            AnyView(emptyState)
        } else {
            AnyView(mainContent)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.on.square")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No assets available")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mainContent: some View {
        GeometryReader { proxy in
            let isLandscape: Bool = proxy.size.width > proxy.size.height
            let overlayHeight: CGFloat = proxy.size.height * descriptionHeightRatio
            let boardsHeight: CGFloat = max(proxy.size.height - overlayHeight, 0)

            Group {
                if isLandscape {
                    HStack(spacing: 0) {
                        boardsSection(height: proxy.size.height)
                            .frame(width: proxy.size.width * 0.6, alignment: .top)

                        descriptionOverlay(
                            containerHeight: proxy.size.height,
                            overlayHeight: proxy.size.height,
                            allowsExpansion: false
                        )
                        .frame(width: proxy.size.width * 0.4, height: proxy.size.height)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    VStack(spacing: 0) {
                        boardsSection(height: boardsHeight)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .safeAreaInset(edge: .bottom) {
                        descriptionOverlay(
                            containerHeight: proxy.size.height,
                            overlayHeight: overlayHeight,
                            allowsExpansion: true
                        )
                    }
                }
            }
        }
    }

    private func boardsSection(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            StackedAssetScroller(
                frame: frame,
                assetStack: assetStack,
                visibleAssetID: $visibleAssetID,
                primaryText: primaryText
            )

            boardCarouselTabs
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height, alignment: .top)
    }

    private var primaryText: String? {
        if let caption: String = frame.caption, !caption.isEmpty { return caption }
        return nil
    }

    private var secondaryText: String? {
        if let description: String = frame.description, !description.isEmpty { return description }
        return nil
    }

    @ViewBuilder
    private var descriptionSection: some View {
        if let secondaryText {
            let cleanText = plainTextFromHTML(secondaryText)
            VStack(alignment: .leading, spacing: 8) {
                Text("Description")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(cleanText)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.9))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Description")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("No description provided for this frame.")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func descriptionOverlay(containerHeight: CGFloat, overlayHeight: CGFloat, allowsExpansion: Bool) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 44, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)

                descriptionSection
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: DescriptionScrollOffsetKey.self, value: proxy.frame(in: .named("descriptionScroll")).minY)
                }
            )
        }
        .coordinateSpace(name: "descriptionScroll")
        .frame(maxWidth: .infinity)
        .frame(height: overlayHeight)
        .background(Color.black)
        .scrollDisabled(allowsExpansion ? !isDescriptionExpanded : false)
        .onPreferenceChange(DescriptionScrollOffsetKey.self) { offset in
            descriptionScrollOffset = offset
            handleDescriptionScroll(offset: offset)
        }
        .gesture(
            descriptionDragGesture(containerHeight: containerHeight),
            including: allowsExpansion ? .all : .none
        )
        .onTapGesture {
            guard allowsExpansion else { return }
            setDescriptionExpanded(true)
        }
    }

    private func handleDescriptionScroll(offset: CGFloat) {
        let collapseThreshold: CGFloat = 18

        if isDescriptionExpanded && offset > collapseThreshold && !isDraggingDescription {
            setDescriptionExpanded(false)
        }
    }

    @ViewBuilder
    private var boardCarouselTabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(assetStack) { asset in
                        let isSelected: Bool = (asset.id == visibleAssetID)
                        Button {
                            visibleAssetID = asset.id
                        } label: {
                            Text(asset.label ?? asset.kind.displayName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(isSelected ? Color.white : Color.primary)
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .frame(minWidth: 80)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                                )
                        }
                        .buttonStyle(.plain)
                        .id(asset.id)
                    }
                }
                .padding(.horizontal, 20)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .onChange(of: visibleAssetID) { (id: FrameAssetItem.ID?) in
                guard let id else { return }
                withAnimation(.snappy(duration: 0.25)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .onAppear {
                guard let id: FrameAssetItem.ID = visibleAssetID else { return }
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    private func loadClips(force: Bool) async {
        var shootId: String?
        let shouldSkip = await MainActor.run { () -> Bool in
            if isLoadingClips { return true }
            if !force && !clips.isEmpty { return true }
            shootId = authService.projectId
            if shootId == nil {
                clipsError = "Missing project ID"
                return true
            }
            isLoadingClips = true
            return false
        }

        if shouldSkip { return }
        guard let shootId else { return }

        do {
            let fetched = try await authService.fetchClips(
                shootId: shootId,
                frameId: frame.id,
                creativeId: frame.creativeId
            )
            await MainActor.run {
                clips = fetched
                filesBadgeCount = fetched.count
                clipsError = nil
            }
        } catch {
            await MainActor.run {
                clipsError = error.localizedDescription
            }
        }
        await MainActor.run {
            isLoadingClips = false
        }
    }

    private func updateStatus(to status: FrameStatus) {
        let updatedFrame = frame.updatingStatus(status)

        withAnimation(.easeInOut(duration: 0.2)) {
            selectedStatus = status
        }

        frame = updatedFrame
        onStatusSelected(updatedFrame, status)
    }

    private func syncWithProvidedFrame() {
        frame = providedFrame
        selectedStatus = providedFrame.statusEnum
        let newStack: [FrameAssetItem] = FrameView.orderedAssets(for: providedFrame, order: assetOrder)
        assetStack = newStack
        visibleAssetID = newStack.first?.id
        clips = []
        filesBadgeCount = nil
        clipsError = nil
        Task {
            await loadClips(force: true)
        }
    }

    @ViewBuilder
    private func statusMenuButton(title: String, status: FrameStatus, systemImage: String) -> some View {
        let isSelected: Bool = (selectedStatus == status)

        Button {
            updateStatus(to: status)
        } label: {
            Label(title, systemImage: systemImage)
                .foregroundStyle(Color.primary)
        }
        .accessibilityLabel("Set status to \(title)")
        .disabled(isSelected)
    }

    private static func orderedAssets(for frame: Frame, order: [FrameAssetKind]) -> [FrameAssetItem] {
        let available = frame.availableAssets

        guard !available.isEmpty else { return [placeholderBoardAsset] }
        var ordered: [FrameAssetItem] = []

        for kind in order {
            let matches = available.filter { $0.kind == kind && !ordered.contains($0) }
            ordered.append(contentsOf: matches)
        }

        for asset in available where !ordered.contains(asset) {
            ordered.append(asset)
        }

        return ordered
    }

    private static let placeholderBoardAsset = FrameAssetItem(kind: .board, primary: nil, fallback: nil)
}

private extension FrameView {
    private var isDescriptionExpanded: Bool {
        descriptionHeightRatio > 0.75
    }

    private func descriptionDragGesture(containerHeight: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if isDraggingDescription == false { isDraggingDescription = true }
                if dragStartRatio == nil { dragStartRatio = descriptionHeightRatio }

                let startingRatio: CGFloat = dragStartRatio ?? descriptionHeightRatio
                let translationRatio: CGFloat = -value.translation.height / containerHeight
                let proposedRatio: CGFloat = startingRatio + translationRatio
                descriptionHeightRatio = min(max(proposedRatio, minDescriptionRatio), 1.0)
            }
            .onEnded { value in
                let startingRatio: CGFloat = dragStartRatio ?? descriptionHeightRatio
                let translationRatio: CGFloat = -value.translation.height / containerHeight
                let proposedRatio: CGFloat = min(max(startingRatio + translationRatio, minDescriptionRatio), 1.0)

                let traveled: CGFloat = abs(proposedRatio - startingRatio)
                let snapThreshold: CGFloat = 0.1
                let targetExpanded: Bool

                if traveled < snapThreshold {
                    targetExpanded = startingRatio > 0.5
                } else {
                    targetExpanded = translationRatio > 0
                }

                setDescriptionExpanded(targetExpanded)
                dragStartRatio = nil
                isDraggingDescription = false
            }
    }

    private func setDescriptionExpanded(_ expanded: Bool) {
        let targetRatio: CGFloat = expanded ? 1.0 : minDescriptionRatio
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            descriptionHeightRatio = targetRatio
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
                                Circle().fill(Color.blue.opacity(0.2)).frame(width: 28, height: 28)
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
                        // Input-like field that acts like a button
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

private struct CommentsPage: View {
    let frameNumber: Int
    @State private var newCommentText: String = ""
    @FocusState private var composeFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(0..<30), id: \.self) { index in
                    let idx: Int = index + 1
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Circle().fill(Color.blue.opacity(0.2)).frame(width: 28, height: 28)
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
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, 24)
        }
        .navigationTitle("Comments")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
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

private struct FilesSheet: View {
    let frame: Frame
    @Binding var clips: [Clip]
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?
    let onReload: () async -> Void
    @State private var selectedClip: Clip?
    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Files for Frame \(frame.frameNumber)")
                .navigationBarTitleDisplayMode(.inline)
                .task {
                    await onReload()
                }
                .alert("Error", isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )) {
                    Button("OK", role: .cancel) { errorMessage = nil }
                } message: {
                    Text(errorMessage ?? "Unknown error")
                }
        }
    }

    private var content: some View {
        Group {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading clips...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !clips.isEmpty {
                List(clips) { clip in
                    ClipRow(clip: clip) {
                        selectedClip = clip
                    }
                }
                .listStyle(.plain)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("No files found")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(item: $selectedClip) { clip in
            ClipPreviewView(clip: clip)
                .presentationDragIndicator(.visible)
        }
        .refreshable {
            await onReload()
        }
    }
}

private struct ClipRow: View {
    let clip: Clip
    let onPreview: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ClipThumbnailView(clip: clip)
                .frame(width: 48, height: 48)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                Text(clip.displayName)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let size = clip.formattedFileSize {
                        Label(size, systemImage: "externaldrive.badge.icloud")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if clip.isVideo {
                        Label("Video", systemImage: "video")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if clip.isImage {
                        Label("Image", systemImage: "photo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()

            Menu {
                Button("Preview") { onPreview() }
                if let url = clip.fileURL {
                    ShareLink(item: url) {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                }
                if clip.isImage || clip.isVideo {
                    Button(role: .none) {
                        saveToPhotos(clip: clip)
                    } label: {
                        Label("Save to Photos", systemImage: "square.and.arrow.down")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onPreview() }
    }

    private func saveToPhotos(clip: Clip) {
        guard let url = clip.fileURL else { return }

        let task = URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data else { return }
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
            do {
                try data.write(to: tempURL)
                Task {
                    if clip.isVideo {
                        await saveVideoToPhotos(url: tempURL)
                    } else {
                        await saveImageToPhotos(data: data)
                    }
                }
            } catch {
                print("Failed to save to temporary file: \(error)")
            }
        }
        task.resume()
    }
}

private struct ClipThumbnailView: View {
    let clip: Clip

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.secondary.opacity(0.15))
            if let url = clip.thumbnailURL {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    ProgressView()
                }
            } else {
                Image(systemName: clip.isVideo ? "video" : "doc")
                    .foregroundStyle(.secondary)
            }
        }
        .clipped()
    }
}

private struct ClipPreviewView: View {
    let clip: Clip

    var body: some View {
        VStack {
            if clip.isVideo, let url = clip.fileURL {
                VideoPlayerContainer(url: url)
            } else if let url = clip.fileURL {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } placeholder: {
                    ProgressView()
                }
            } else {
                Text("Unable to load clip")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

private struct VideoPlayerContainer: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> some UIViewController {
        let controller = AVPlayerViewController()
        controller.player = AVPlayer(url: url)
        controller.player?.play()
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {
    }
}

@MainActor
private func saveImageToPhotos(data: Data) async {
    guard let image = UIImage(data: data) else { return }
    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
}

@MainActor
private func saveVideoToPhotos(url: URL) async {
    UISaveVideoAtPathToSavedPhotosAlbum(url.path, nil, nil, nil)
}

enum FrameNavigationDirection {
    case previous
    case next
}

private extension View {
    @ViewBuilder
    func applyHorizontalScrollTransition() -> some View {
        self.scrollTransition(.interactive, axis: .horizontal) { content, phase in
            let value: CGFloat = phase.value
            let isIdentity: Bool = phase.isIdentity
            let incomingNudge: CGFloat = max(0, value) * 24
            let stackedShift: CGFloat  = min(0, value) * 12
            let rawOffset: CGFloat = incomingNudge + stackedShift
            let offsetX: CGFloat = isIdentity ? 0 : rawOffset
            let scaleNegative: CGFloat = 0.5
            let scalePositive: CGFloat = 1.01
            let scaleIdentity: CGFloat = 1
            let scale: CGFloat = isIdentity ? scaleIdentity : (value < 0 ? scaleNegative : scalePositive)
            return content
                .offset(x: offsetX)
                .scaleEffect(scale)
        }
    }
}

private struct DescriptionScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension FrameStatus {
    var displayName: String {
        switch self {
        case .done:
            return "Done"
        case .inProgress:
            return "Here"
        case .skip:
            return "Omit"
        case .upNext:
            return "Next"
        case .none:
            return "Clear"
        }
    }

    var systemImageName: String {
        switch self {
        case .done:
            return "checkmark.circle"
        case .inProgress:
            return "figure.wave"
        case .upNext:
            return "arrow.turn.up.right"
        case .skip:
            return "minus.circle"
        case .none:
            return "xmark.circle"
        }
    }

    var labelColor: Color {
        switch self {
        case .done, .skip:
            return .red
        case .inProgress:
            return .green
        case .upNext:
            return .orange
        case .none:
            return .white
        }
    }
}

private struct StackedAssetScroller: View {
    let frame: Frame
    let assetStack: [FrameAssetItem]
    @Binding var visibleAssetID: FrameAssetItem.ID?
    let primaryText: String?

    var body: some View {
        GeometryReader { proxy in
            let cardWidth: CGFloat = proxy.size.width * 0.82
            let cardHeight: CGFloat = cardWidth * 1.15

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .center, spacing: 0) {
                    ForEach(assetStack) { asset in
                        AssetCardView(
                            frame: frame,
                            asset: asset,
                            cardWidth: cardWidth,
                            primaryText: primaryText
                        )
                        .id(asset.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $visibleAssetID)
            .contentMargins(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight)
        }
        .frame(minHeight: UIScreen.main.bounds.width * 0.82 * 1.15)
    }
}

private struct AssetCardView: View {
    let frame: Frame
    let asset: FrameAssetItem
    let cardWidth: CGFloat
    let primaryText: String?

    var body: some View {
        FrameLayout(
            frame: frame,
            primaryAsset: asset,
            title: primaryText,
            showStatusBadge: true,
            showFrameNumberOverlay: true,
            showTextBlock: false,
            cornerRadius: 16
        )
        .frame(width: cardWidth)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .applyHorizontalScrollTransition()
        .shadow(radius: 10, x: 0, y: 10)
    }
}
//
//#Preview {
//    let sample = Frame(
//        id: "1",
//        creativeId: "c1",
//        board: "https://example.com/board.jpg",
//        frameOrder: "1",
//        photoboard: "https://example.com/photoboard.jpg",
//        preview: "https://example.com/preview.mp4",
//        previewThumb: "https://example.com/preview_thumb.jpg",
//        description: "A sample description.",
//        caption: "Sample Caption",
//        status: FrameStatus.inProgress.rawValue
//    )
//    FrameView(frame: sample, assetOrder: .constant([.board, .photoboard, .preview])) {}
//}
