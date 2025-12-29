import SwiftUI
import AVKit
import UIKit
import Combine
import QuickLook
import Photos
import UniformTypeIdentifiers

@MainActor
struct FrameView: View {
    private let providedFrame: Frame
    @EnvironmentObject private var authService: AuthService
    @Environment(\.fullscreenMediaCoordinator) private var fullscreenCoordinator
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
    @State private var filesSheetDetent: PresentationDetent = .medium
    @State private var clips: [Clip] = []
    @State private var isLoadingClips: Bool = false
    @State private var clipsError: String?
    @State private var filesBadgeCount: Int? = nil
    @State private var comments: [Comment] = []
    @State private var isLoadingComments: Bool = false
    @State private var commentsError: String?
    @State private var commentsBadgeCount: Int? = nil
    @State private var descriptionHeightRatio: CGFloat
    @State private var dragStartRatio: CGFloat?
    @State private var descriptionScrollOffset: CGFloat = 0
    @State private var isDraggingDescription: Bool = false
    @State private var isUpdatingStatus: Bool = false
    @State private var statusUpdateError: String?
    @State private var showingStatusSheet: Bool = false
    @State private var sheetVisible: Bool = false
    @State private var statusBeingUpdated: FrameStatus?
    @State private var showingScoutCamera: Bool = false
    @State private var showingScoutCameraWarning: Bool = false
    @State private var showingScoutCameraSettings: Bool = false
    @State private var showingBoardRenameAlert: Bool = false
    @State private var boardRenameText: String = ""
    @State private var boardRenameTarget: FrameAssetItem?
    @State private var isRenamingBoard: Bool = false
    @State private var showingBoardReorderSheet: Bool = false
    @State private var reorderBoards: [FrameAssetItem] = []
    @State private var activeReorderBoard: FrameAssetItem?
    @State private var showingBoardDeleteAlert: Bool = false
    @State private var boardDeleteTarget: FrameAssetItem?
    @State private var boardActionError: String?

    private let minDescriptionRatio: CGFloat = 0.35
    private let dimmerAnim = Animation.easeInOut(duration: 0.28)
    private let sheetAnim = Animation.spring(response: 0.42, dampingFraction: 0.92, blendDuration: 0.20)
    private let takePictureCardID = "take-picture"
    private let selectionStore = ProjectKitSelectionStore.shared
    private let dataStore = LocalJSONStore.shared

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
        _descriptionHeightRatio = State(initialValue: minDescriptionRatio)
    }

    private var frameTitle: String {
        if frame.frameNumber > 0 {
            return "Frame \(frame.frameNumber)"
        }
        return "Frame"
    }

    var body: some View {
        fullContent
    }

    private var fullContent: some View {
        scoutCameraContent
            .alert("Scout Camera Setup Needed", isPresented: $showingScoutCameraWarning) {
                Button("Cancel", role: .cancel) {}
                Button("Go To Settings") {
                    showingScoutCameraSettings = true
                }
            } message: {
                Text("Select at least one camera and lens in settings to use Scout Camera.")
            }
    }

    private var scoutCameraContent: some View {
        overlayContent
            .fullScreenCover(isPresented: $showingScoutCamera) {
                if let projectId = authService.projectId {
                    ScoutCameraLayout(
                        projectId: projectId,
                        frameId: frame.id,
                        targetAspectRatio: frameAspectRatio
                    )
                    .environmentObject(authService)
                }
            }
            .sheet(isPresented: $showingScoutCameraSettings) {
                ScoutCameraSettingsSheet()
                    .environmentObject(authService)
            }
    }

    private var overlayContent: some View {
        eventDrivenContent
            .overlay(alignment: .center) {
                fullscreenOverlay
            }
            .overlay(alignment: .bottom) {
                statusSheetOverlay
            }
            .animation(.easeInOut(duration: 0.25), value: fullscreenCoordinator?.configuration?.id)
    }

    private var eventDrivenContent: some View {
        badgeContent
            .task {
                await loadClips(force: false)
                await loadComments(force: false)
            }
            .onChange(of: providedFrame.id) { _ in
                syncWithProvidedFrame()
            }
            .onChange(of: authService.projectId) { newProjectId in
                guard newProjectId != nil else { return }
                Task {
                    await loadClips(force: false)
                    await loadComments(force: false)
                }
            }
            .onReceive(authService.$frames) { frames in
                guard let updated = frames.first(where: { $0.id == frame.id }) else { return }
                frame = updated
                selectedStatus = updated.statusEnum

                let newStack: [FrameAssetItem] = FrameView.orderedAssets(for: updated, order: assetOrder)
                if assetStack.map(\.id) != newStack.map(\.id) {
                    assetStack = newStack
                    if visibleAssetID == nil { visibleAssetID = newStack.first?.id }
                }
            }
            .onReceive(authService.$frameUpdateEvent) { event in
                guard let event else { return }
                guard event.frameId == frame.id else { return }
                guard case .websocket(let eventName) = event.context, eventName == "update-clips" else { return }
                Task {
                    await loadClips(force: true)
                }
            }
    }

    private var badgeContent: some View {
        assetOrderContent
            .onChange(of: clips) { newClips in
                filesBadgeCount = newClips.count
            }
            .onChange(of: comments) { newComments in
                commentsBadgeCount = totalCommentCount(in: newComments)
            }
    }

    private var assetOrderContent: some View {
        filesSheetContent
            .onChange(of: assetOrder) { (newOrder: [FrameAssetKind]) in
                let newStack: [FrameAssetItem] = FrameView.orderedAssets(for: frame, order: newOrder)
                assetStack = newStack
                if visibleAssetID == nil { visibleAssetID = newStack.first?.id }
            }
            .onChange(of: assetStack) { (newStack: [FrameAssetItem]) in
                assetOrder = newStack.map(\.kind)
                let newIDs = Set(newStack.map(\.id))
                if let currentID = visibleAssetID, !newIDs.contains(currentID), currentID != takePictureCardID {
                    visibleAssetID = newStack.first?.id
                } else if visibleAssetID == nil, let first: FrameAssetItem.ID = newStack.first?.id {
                    visibleAssetID = first
                }
            }
    }

    private var filesSheetContent: some View {
        boardActionContent
            .sheet(isPresented: $showingFiles) {
                FilesSheet(
                    frame: frame,
                    clips: $clips,
                    isLoading: $isLoadingClips,
                    errorMessage: $clipsError,
                    onReload: { await loadClips(force: true) }
                )
                .presentationDetents([.medium, .large], selection: $filesSheetDetent)
                .presentationDragIndicator(.visible)
            }
            .onChange(of: showingFiles) { isShowing in
                if isShowing {
                    filesSheetDetent = .medium
                }
            }
    }

    private var boardActionContent: some View {
        statusAlertContent
            .sheet(isPresented: $showingBoardReorderSheet) {
                BoardReorderSheet(
                    boards: $reorderBoards,
                    activeBoard: $activeReorderBoard,
                    onSave: { saveBoardReorder() }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .alert(
                "Remove Board?",
                isPresented: $showingBoardDeleteAlert,
                presenting: boardDeleteTarget
            ) { _ in
                Button("Cancel", role: .cancel) {}
                Button("Continue", role: .destructive) {
                    if let target = boardDeleteTarget {
                        deleteBoard(target)
                    }
                }
            } message: { target in
                Text("Are you sure you want to remove \(target.displayLabel)?")
            }
            .alert(
                "Unable to Update Board",
                isPresented: Binding(
                    get: { boardActionError != nil },
                    set: { if !$0 { boardActionError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { boardActionError = nil }
            } message: {
                Text(boardActionError ?? "An unknown error occurred.")
            }
            .overlay {
                if showingBoardRenameAlert {
                    BoardRenameAlert(
                        boardName: boardRenameTarget?.displayLabel ?? "Board",
                        name: $boardRenameText,
                        isSaving: isRenamingBoard,
                        onCancel: {
                            showingBoardRenameAlert = false
                            boardRenameTarget = nil
                        },
                        onSave: {
                            Task {
                                isRenamingBoard = true
                                let didSave = await renameBoard()
                                isRenamingBoard = false
                                if didSave {
                                    showingBoardRenameAlert = false
                                }
                            }
                        }
                    )
                }
            }
    }

    private var statusAlertContent: some View {
        baseContent
            .alert(
                "Unable to Update Status",
                isPresented: statusUpdateAlertBinding
            ) {
                Button("OK", role: .cancel) { statusUpdateError = nil }
            } message: {
                Text(statusUpdateError ?? "An unknown error occurred.")
            }
    }

    private var baseContent: some View {
        contentView
            .navigationTitle(frameTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                topToolbar
                bottomToolbar
            }
    }

    private var statusUpdateAlertBinding: Binding<Bool> {
        Binding(
            get: { statusUpdateError != nil },
            set: { if !$0 { statusUpdateError = nil } }
        )
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
                Image(systemName: "arrow.left")
            }
            .accessibilityLabel("Previous frame")
            .disabled(!hasPreviousFrame)

            Button {
                onNavigate(.next)
            } label: {
                Image(systemName: "arrow.right")
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
                toolbarIconBadge(title: "Files", systemName: "folder", count: filesBadgeCount)
            }


            Spacer()

            Button {
                openStatusSheet()
            } label: {
                let statusLabel: String = {
                    if isUpdatingStatus { return "Updating Status" }
                    return selectedStatus == .none ? "Mark Frame" : selectedStatus.displayName
                }()
                Label {
                    Text(statusLabel)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                } icon: {
                    if isUpdatingStatus {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: selectedStatus == .none ? "pencil.tip" : selectedStatus.systemImageName)
                    }
                }
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(selectedStatus.markerBackgroundColor)
                )
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
//                .shadow(color: selectedStatus.markerBackgroundColor.opacity(0.8), radius: 12, x: 0, y: 0)
//                .shadow(color: selectedStatus.markerBackgroundColor.opacity(0.5), radius: 50, x: 0, y: 0)
//                .shadow(color: selectedStatus.markerBackgroundColor.opacity(0.3), radius: 100, x: 0, y: 0)
            }
            .buttonStyle(.plain)
            .disabled(isUpdatingStatus)
            //.tint(.yellow)

            Spacer()

            NavigationLink {
                CommentsPage(
                    frameNumber: frame.frameNumber,
                    comments: comments,
                    isLoading: isLoadingComments,
                    errorMessage: commentsError,
                    onReload: { await loadComments(force: true) }
                )
            } label: {
                toolbarIconBadge(title: "Comments", systemName: "text.bubble", count: commentsBadgeCount)
            }
            
            
        }
    }

    @ViewBuilder
    private func toolbarIconBadge(title: String, systemName: String, count: Int?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .accessibilityLabel(title)

            if let count, count > 0 {
                Text(count > 99 ? "99+" : "\(count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.martiniDefault))
                    .monospacedDigit()
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
            let boardsHeight: CGFloat = max(0, proxy.size.height - overlayHeight)
            let descriptionProgress: CGFloat = max(
                0,
                min(
                    1,
                    (descriptionHeightRatio - minDescriptionRatio) / (1 - minDescriptionRatio)
                )
            )
            let dimmerOpacity: CGFloat = descriptionProgress * 0.5

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
                    ZStack(alignment: .bottom) {
                        boardsSection(height: boardsHeight)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                        Color.black
                            .opacity(dimmerOpacity)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)

                        descriptionOverlay(
                            containerHeight: proxy.size.height,
                            overlayHeight: overlayHeight,
                            allowsExpansion: true
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
        }
    }

    private var statusSheetOverlay: some View {
        ZStack(alignment: .bottom) {
            if showingStatusSheet {
                // Dimmer (gentle, native)
                Color.black
                    .opacity(sheetVisible ? 0.7 : 0)
                    .ignoresSafeArea()
                    .animation(dimmerAnim, value: sheetVisible)
                    .onTapGesture {
                        guard !isUpdatingStatus else { return }
                        closeStatusSheet()
                    }

                // Sheet (native spring)
                sheetContent
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .offset(y: sheetVisible ? 0 : 420)
                    .animation(sheetAnim, value: sheetVisible)
                    .frame(maxWidth: .infinity)
                    .frame(height: 100)
            }
        }
    }

    private var sheetContent: some View {
        HStack(spacing: 0) {
            statusSelectionButton(for: .here)
            Divider()
            statusSelectionButton(for: .next)
            Divider()
            statusSelectionButton(for: .done)
            Divider()
            statusSelectionButton(for: .omit)
            if selectedStatus != .none {
                Divider()
                statusSelectionButton(for: .none)
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.markerPopup).opacity(1))
        )
    }

    private func openStatusSheet() {
        showingStatusSheet = true
        DispatchQueue.main.async {
            sheetVisible = true
        }
    }

    private func closeStatusSheet() {
        sheetVisible = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            showingStatusSheet = false
        }
    }

    private func boardsSection(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            StackedAssetScroller(
                frame: frame,
                assetStack: assetStack,
                visibleAssetID: $visibleAssetID,
                primaryText: primaryText,
                takePictureID: takePictureCardID,
                takePictureAction: {
                    openScoutCamera()
                },
                contextMenuContent: { asset in
                    boardContextMenu(for: asset)
                }
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

    @ViewBuilder
    private func boardContextMenu(for asset: FrameAssetItem) -> some View {
        if asset.kind == .board {
            let isBoardEntry = boardEntry(for: asset) != nil
            if isBoardEntry {
                Button("Rename") {
                    boardRenameTarget = asset
                    boardRenameText = asset.displayLabel
                    isRenamingBoard = false
                    showingBoardRenameAlert = true
                }
                Button("Reorder") {
                    reorderBoards = boardEntries()
                    showingBoardReorderSheet = true
                }
                Button("Pin board") {
                    pinBoard(asset)
                }
                Button("Delete", role: .destructive) {
                    boardDeleteTarget = asset
                    showingBoardDeleteAlert = true
                }
            } else {
                Button("Delete", role: .destructive) {
                    boardDeleteTarget = asset
                    showingBoardDeleteAlert = true
                }
            }
        }
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
                if allowsExpansion {
                    Capsule()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 44, height: 5)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                } else {
                    Color.clear
                        .frame(height: 10)
                        .frame(maxWidth: .infinity)
                }

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
        .simultaneousGesture(
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
                                        .fill(isSelected ? Color.martiniDefaultColor : Color.secondary.opacity(0.15))
                                )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            boardContextMenu(for: asset)
                        }
                        .id(asset.id)
                    }

                    Button {
                        openScoutCamera()
                    } label: {
                        HStack(spacing: 4) {
                            Label("Add Photo", systemImage: "plus")
                            //Text("Add Photo")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .frame(minWidth: 100)
                                .background(
                                    Capsule()
                                        .fill(Color.secondary.opacity(0.15))
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .id(takePictureCardID)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, alignment: .center)
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
        if isLoadingClips { return }
        if !force && !clips.isEmpty { return }
        guard let shootId = authService.projectId else {
            clipsError = "Missing project ID"
            return
        }

        isLoadingClips = true
        defer { isLoadingClips = false }

        do {
            let fetched = try await authService.fetchClips(
                shootId: shootId,
                frameId: frame.id,
                creativeId: frame.creativeId
            )
            guard !Task.isCancelled else { return }
            clips = fetched
            filesBadgeCount = fetched.count
            clipsError = nil
        } catch is CancellationError {
            return
        } catch {
            clipsError = error.localizedDescription
        }
    }

    private func loadComments(force: Bool) async {
        if isLoadingComments { return }
        if !force && !comments.isEmpty { return }

        isLoadingComments = true
        defer { isLoadingComments = false }

        do {
            let response = try await authService.fetchComments(
                creativeId: frame.creativeId,
                frameId: frame.id
            )
            guard !Task.isCancelled else { return }
            comments = response.comments
            commentsBadgeCount = totalCommentCount(in: response.comments)
            commentsError = nil
        } catch is CancellationError {
            return
        } catch {
            commentsError = error.localizedDescription
        }
    }

    private func updateStatus(to status: FrameStatus) {
        guard !isUpdatingStatus else { return }
        isUpdatingStatus = true
        statusBeingUpdated = status
        Task {
            do {
                let updatedFrame = try await authService.updateFrameStatus(id: frame.id, to: status)
                triggerStatusHaptic(for: status)

                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedStatus = updatedFrame.statusEnum
                    }

                    frame = updatedFrame
                    onStatusSelected(updatedFrame, updatedFrame.statusEnum)
                    closeStatusSheet()
                }
            } catch {
                await MainActor.run {
                    statusUpdateError = error.localizedDescription
                }
            }

            await MainActor.run {
                isUpdatingStatus = false
                statusBeingUpdated = nil
            }
        }
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
        comments = []
        commentsBadgeCount = nil
        commentsError = nil
        descriptionHeightRatio = minDescriptionRatio
        closeStatusSheet()
        Task {
            await loadClips(force: true)
            await loadComments(force: true)
        }
    }

    private func openScoutCamera() {
        guard let projectId = authService.projectId else {
            showingScoutCamera = true
            return
        }
        let cameraIds = selectionStore.cameraIds(for: projectId)
        let lensIds = selectionStore.lensIds(for: projectId)
        let availableCameras = dataStore.fetchCameras(ids: cameraIds)
        let availableLenses = dataStore.fetchLenses(ids: lensIds)
        guard !availableCameras.isEmpty && !availableLenses.isEmpty else {
            showingScoutCameraWarning = true
            return
        }
        showingScoutCamera = true
    }

    @ViewBuilder
    private func statusSelectionButton(for status: FrameStatus) -> some View {
        let isSelected: Bool = (selectedStatus == status)
        let isLoading: Bool = isUpdatingStatus && statusBeingUpdated == status

        Button {
            updateStatus(to: status)
        } label: {
            VStack(spacing: 12) {
                Group {
                    if isLoading {
                        ProgressView()
                            .tint(status.markerBackgroundColor)
                    } else {
                        Image(systemName: status.systemImageName)
                            .font(.system(size: 25, weight: .semibold))
                            .foregroundStyle(status.markerBackgroundColor)
                    }
                }
                .frame(width: 40, height: 40)
                //.background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                Text(status.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .center)
//            .background(
//                RoundedRectangle(cornerRadius: 12)
//                    .fill(Color(.secondarySystemBackground))
//            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set status to \(status.displayName)")
        .disabled(isSelected || isUpdatingStatus)
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

    private static let placeholderBoardAsset = FrameAssetItem(
        id: "placeholder-board",
        kind: .board,
        primary: nil,
        fallback: nil
    )
}

private extension FrameView {
    private var isDescriptionExpanded: Bool {
        descriptionHeightRatio > 0.75
    }

    private var canDragDescription: Bool {
        !isDescriptionExpanded || descriptionScrollOffset >= 0
    }

    private var frameAspectRatio: CGFloat {
        parseAspectRatio(frame.creativeAspectRatio)
    }

    private func parseAspectRatio(_ ratio: String?) -> CGFloat {
        guard let ratio else { return 16.0 / 9.0 }
        let cleaned = ratio.lowercased().replacingOccurrences(of: " ", with: "")
        if cleaned.contains(":") {
            let parts = cleaned.split(separator: ":")
            if parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]), h != 0 {
                return CGFloat(w / h)
            }
        }
        if cleaned.contains("x") {
            let parts = cleaned.split(separator: "x")
            if parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]), h != 0 {
                return CGFloat(w / h)
            }
        }
        if let value = Double(cleaned), value > 0 {
            return CGFloat(value)
        }
        return 16.0 / 9.0
    }

    private func boardEntry(for asset: FrameAssetItem) -> FrameBoard? {
        frame.boards?.first { $0.id == asset.id }
    }

    private func boardEntries() -> [FrameAssetItem] {
        let boardIds = Set(frame.boards?.map(\.id) ?? [])
        return assetStack.filter { asset in
            asset.kind == .board && boardIds.contains(asset.id)
        }
    }

    private func renameBoard() async -> Bool {
        guard let target = boardRenameTarget else { return false }
        guard let boardId = boardEntry(for: target)?.id else {
            boardActionError = "Board ID not found for rename."
            return false
        }
        let trimmedLabel = boardRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty else { return false }

        do {
            try await authService.renameBoard(frameId: frame.id, boardId: boardId, label: trimmedLabel)
            boardRenameTarget = nil
            return true
        } catch {
            boardActionError = error.localizedDescription
            return false
        }
    }

    private func saveBoardReorder() {
        let boardsToReorder = reorderBoards
        guard !boardsToReorder.isEmpty else { return }

        let orders: [[String: Any]] = boardsToReorder.enumerated().map { index, board in
            [
                "boardId": board.id,
                "order": index + 1
            ]
        }

        Task {
            do {
                try await authService.reorderBoards(frameId: frame.id, orders: orders)
                activeReorderBoard = nil
            } catch {
                boardActionError = error.localizedDescription
            }
        }
    }

    private func pinBoard(_ asset: FrameAssetItem) {
        guard let boardId = boardEntry(for: asset)?.id else {
            boardActionError = "Board ID not found for pinning."
            return
        }

        Task {
            do {
                try await authService.pinBoard(frameId: frame.id, boardId: boardId)
            } catch {
                boardActionError = error.localizedDescription
            }
        }
    }

    private func deleteBoard(_ asset: FrameAssetItem) {
        if let boardId = boardEntry(for: asset)?.id {
            Task {
                do {
                    try await authService.deleteBoard(frameId: frame.id, boardId: boardId)
                    boardDeleteTarget = nil
                } catch {
                    boardActionError = error.localizedDescription
                }
            }
            return
        }

        let fallbackLabel = "Storyboard"
        Task {
            do {
                try await authService.removeBoardImage(frameId: frame.id, boardLabel: fallbackLabel)
                boardDeleteTarget = nil
            } catch {
                boardActionError = error.localizedDescription
            }
        }
    }

    private func totalCommentCount(in comments: [Comment]) -> Int {
        comments.reduce(0) { partial, comment in
            partial + 1 + totalCommentCount(in: comment.replies)
        }
    }

    @ViewBuilder
    private var fullscreenOverlay: some View {
        if let configuration = fullscreenCoordinator?.configuration {
            FullscreenMediaView(
                url: configuration.url,
                isVideo: configuration.isVideo,
                aspectRatio: configuration.aspectRatio,
                title: configuration.title,
                frameNumberLabel: configuration.frameNumberLabel,
                namespace: configuration.namespace,
                heroID: configuration.heroID,
                onDismiss: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        fullscreenCoordinator?.configuration = nil
                    }
                }
            )
            .transition(.opacity)
            .zIndex(1)
        }
    }

    private func descriptionDragGesture(containerHeight: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard canDragDescription else { return }
                if isDraggingDescription == false { isDraggingDescription = true }
                if dragStartRatio == nil { dragStartRatio = descriptionHeightRatio }

                let startingRatio: CGFloat = dragStartRatio ?? descriptionHeightRatio
                let translationRatio: CGFloat = -value.translation.height / containerHeight
                let proposedRatio: CGFloat = startingRatio + translationRatio
                descriptionHeightRatio = min(max(proposedRatio, minDescriptionRatio), 1.0)
            }
            .onEnded { value in
                guard let startingRatio: CGFloat = dragStartRatio else {
                    isDraggingDescription = false
                    return
                }
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

private struct ScoutCameraSettingsSheet: View {
    var body: some View {
        NavigationStack {
            ScoutCameraSettingsView()
//            .toolbar {
//                ToolbarItem(placement: .topBarLeading) {
//                    Button {
//                        dismiss()
//                    } label: {
//                        Image(systemName: "xmark")
//                    }
//                    .accessibilityLabel("Close settings")
//                }
//            }
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

private struct CommentThreadView: View {
    let comment: Comment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CommentRow(comment: comment, isReply: false)

            if !comment.replies.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(comment.replies) { reply in
                        CommentRow(comment: reply, isReply: true)
                    }
                }
                .padding(.leading, 24)
            }
        }
    }
}

private struct CommentRow: View {
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
            if !clips.isEmpty {
                List(clips) { clip in
                    ClipRow(clip: clip) {
                        selectedClip = clip
                    }
                }
                .listStyle(.plain)
            } else if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading clips...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "folder")
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
    }
}

private struct ClipRow: View {
    let clip: Clip
    let onPreview: () -> Void
    @State private var shareItem: ShareItem?
    @State private var photoAccessAlert: PhotoAccessAlert?
    @Environment(\.openURL) private var openURL

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
                    Button {
                        shareClip(url: url)
                    } label: {
                        Label("Share/Save", systemImage: "square.and.arrow.up")
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
        .sheet(item: $shareItem) { item in
            ActivityView(activityItems: [item.url])
        }
        .alert(item: $photoAccessAlert) { alert in
            Alert(
                title: Text("Photos Access Needed"),
                message: Text(alert.message),
                primaryButton: .default(Text("Open Settings")) {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        openURL(settingsURL)
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func saveToPhotos(clip: Clip) {
        guard let url = clip.fileURL else { return }
        Task {
            do {
                let (downloadedURL, _) = try await URLSession.shared.download(from: url)
                let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: downloadedURL, to: destinationURL)

                let result: PhotoSaveResult
                if clip.isVideo {
                    result = await saveVideoToPhotos(url: destinationURL)
                } else {
                    let data = try Data(contentsOf: destinationURL)
                    result = await saveImageToPhotos(data: data)
                }

                if case .accessDenied = result {
                    photoAccessAlert = PhotoAccessAlert(
                        message: "Martini needs access to your Photos library to save clips. Please enable Photos access in Settings."
                    )
                }
            } catch {
                print("Failed to save clip to Photos: \(error)")
            }
        }
    }

    private func shareClip(url: URL) {
        let task = URLSession.shared.downloadTask(with: url) { tempURL, _, error in
            guard let tempURL else {
                if let error {
                    print("Failed to download clip for sharing: \(error)")
                }
                return
            }
            let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: tempURL, to: destinationURL)
                DispatchQueue.main.async {
                    shareItem = ShareItem(url: destinationURL)
                }
            } catch {
                print("Failed to prepare clip for sharing: \(error)")
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
                Image(systemName: clip.systemIconName)
                    .foregroundStyle(.secondary)
            }
        }
        .clipped()
    }
}

private struct ClipPreviewView: View {
    let clip: Clip
    @State private var localPreviewURL: URL?
    @State private var isLoadingPreview = false
    @State private var previewErrorMessage: String?

    var body: some View {
        VStack {
            if clip.isVideo, let url = clip.fileURL {
                VideoPlayerContainer(url: url)
            } else if clip.isImage, let url = clip.fileURL {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } placeholder: {
                    ProgressView()
                }
            } else if let localPreviewURL {
                QuickLookPreview(url: localPreviewURL)
            } else if isLoadingPreview {
                ProgressView()
            } else {
                Text(previewErrorMessage ?? "Unable to load clip")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .task(id: clip.id) {
            await loadPreview()
        }
    }

    private func loadPreview() async {
        guard !clip.isVideo, !clip.isImage else { return }
        guard localPreviewURL == nil else { return }
        guard let remoteURL = clip.fileURL else {
            previewErrorMessage = "Unable to load file."
            return
        }
        isLoadingPreview = true
        defer { isLoadingPreview = false }
        do {
            let (tempURL, _) = try await URLSession.shared.download(from: remoteURL)
            let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(remoteURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: tempURL, to: destinationURL)
            localPreviewURL = destinationURL
        } catch {
            previewErrorMessage = "Unable to load file."
            print("Failed to download preview file: \(error)")
        }
    }
}

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        context.coordinator.url = url
        uiViewController.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}

private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct PhotoAccessAlert: Identifiable {
    let id = UUID()
    let message: String
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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

private enum PhotoSaveResult {
    case success
    case accessDenied
    case failure(Error)
}

private func saveImageToPhotos(data: Data) async -> PhotoSaveResult {
    guard UIImage(data: data) != nil else {
        return .failure(NSError(domain: "PhotosSave", code: 3, userInfo: nil))
    }
    let accessResult = await requestPhotoLibraryAccess()
    guard accessResult == .authorized else { return .accessDenied }
    do {
        try await performPhotoLibraryChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
        }
        return .success
    } catch {
        print("Failed to save image to Photos: \(error)")
        return .failure(error)
    }
}

private func saveVideoToPhotos(url: URL) async -> PhotoSaveResult {
    guard FileManager.default.fileExists(atPath: url.path) else { return .failure(NSError(domain: "PhotosSave", code: 2, userInfo: nil)) }
    let accessResult = await requestPhotoLibraryAccess()
    guard accessResult == .authorized else { return .accessDenied }
    do {
        try await performPhotoLibraryChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .video, fileURL: url, options: nil)
        }
        return .success
    } catch {
        print("Failed to save video to Photos: \(error)")
        return .failure(error)
    }
}

private enum PhotoLibraryAccessResult {
    case authorized
    case denied
}

private func requestPhotoLibraryAccess() async -> PhotoLibraryAccessResult {
    let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
    switch status {
    case .authorized, .limited:
        return .authorized
    case .notDetermined:
        let newStatus = await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { result in
                continuation.resume(returning: result)
            }
        }
        return (newStatus == .authorized || newStatus == .limited) ? .authorized : .denied
    default:
        return .denied
    }
}

private func performPhotoLibraryChanges(_ changes: @escaping () -> Void) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        PHPhotoLibrary.shared().performChanges(changes) { success, error in
            if let error {
                continuation.resume(throwing: error)
            } else if success {
                continuation.resume(returning: ())
            } else {
                continuation.resume(throwing: NSError(domain: "PhotosSave", code: 1, userInfo: nil))
            }
        }
    }
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
    static func fromAPIValue(_ value: String?) -> FrameStatus {
        guard let value = value?.lowercased() else { return .none }

        switch value {
        case "done":
            return .done
        case "here":
            return .here
        case "next":
            return .next
        case "omit":
            return .omit
        case "", "0", "null":
            return .none
        default:
            return .none
        }
    }

    var requestValue: Any {
        switch self {
        case .none:
            return NSNull()
        default:
            return rawValue
        }
    }

    var displayName: String {
        switch self {
        case .done:
            return "Done"
        case .here:
            return "Here"
        case .next:
            return "Next"
        case .omit:
            return "Omit"
        case .none:
            return "Clear"
        }
    }

    var systemImageName: String {
        AppConfig.MarkerIcons.systemImageName(for: self)
    }

    var labelColor: Color {
        switch self {
        case .done:
            return .red
        case .here:
            return .green
        case .next:
            return .orange
        case .omit:
            return .red
        case .none:
            return .gray
        }
    }

    var markerBackgroundColor: Color {
        switch self {
        case .done:
            return .red
        case .here:
            return .green
        case .next:
            return .orange
        case .omit:
            return .red
        case .none:
            return .markerClear
        }
    }
}

private struct StackedAssetScroller<ContextMenuContent: View>: View {
    let frame: Frame
    let assetStack: [FrameAssetItem]
    @Binding var visibleAssetID: FrameAssetItem.ID?
    let primaryText: String?
    let takePictureID: String
    let takePictureAction: (() -> Void)?
    let contextMenuContent: (FrameAssetItem) -> ContextMenuContent

    var body: some View {
        GeometryReader { proxy in
            let cardWidth: CGFloat = proxy.size.width * 0.82
            let idealHeight: CGFloat = cardWidth * 1.15
            let availableHeight: CGFloat = proxy.size.height
            let maxHeight: CGFloat = availableHeight > 0 ? availableHeight * 0.92 : idealHeight
            let cardHeight: CGFloat = min(idealHeight, maxHeight)
            let cardCornerRadius: CGFloat = 16
            let aspectRatio: CGFloat = FrameLayout.aspectRatio(from: frame.creativeAspectRatio ?? "") ?? (16.0 / 9.0)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .center, spacing: 0) {
                    ForEach(assetStack) { asset in
                        AssetCardView(
                            frame: frame,
                            asset: asset,
                            cardWidth: cardWidth,
                            primaryText: primaryText
                        )
                        .contextMenu {
                            contextMenuContent(asset)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .containerRelativeFrame(.horizontal, alignment: .center)
                        .id(asset.id)
                    }

                    if let takePictureAction {
                        TakePictureCardView(
                            cardWidth: cardWidth,
                            aspectRatio: aspectRatio,
                            cornerRadius: cardCornerRadius,
                            action: takePictureAction
                        )
                            .frame(maxWidth: .infinity, alignment: .center)
                            .containerRelativeFrame(.horizontal, alignment: .center)
                            .id(takePictureID)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $visibleAssetID)
            .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight)
        }
    }
}

private struct AssetCardView: View {
    let frame: Frame
    let asset: FrameAssetItem
    let cardWidth: CGFloat
    let primaryText: String?
    private let cardCornerRadius: CGFloat = 16

    var body: some View {
        FrameLayout(
            frame: frame,
            primaryAsset: asset,
            title: primaryText,
            showStatusBadge: true,
            showFrameNumberOverlay: true,
            showPinnedBoardOverlay: true,
            showTextBlock: false,
            cornerRadius: cardCornerRadius
        )
        .frame(width: cardWidth)
        .padding(.vertical, 16)
        .applyHorizontalScrollTransition()
        .shadow(radius: 10, x: 0, y: 10)
    }
}

private struct TakePictureCardView: View {
    let cardWidth: CGFloat
    let aspectRatio: CGFloat
    let cornerRadius: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
                VStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(Color.primary)
                    Text("Scout Camera")
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                }
            }
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(width: cardWidth)
            .padding(.vertical, 16)
            .shadow(radius: 10, x: 0, y: 10)
        }
        .buttonStyle(.plain)
    }
}

private struct BoardRenameAlert: View {
    let boardName: String
    @Binding var name: String
    let isSaving: Bool
    let onCancel: () -> Void
    let onSave: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isSaving {
                        onCancel()
                    }
                }

            VStack(alignment: .leading, spacing: 16) {
                Text("Rename Board")
                    .font(.title3.weight(.semibold))
                Text("Update the label for \(boardName).")
                    .foregroundStyle(.secondary)
                TextField("Board name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onAppear {
                        isFocused = true
                    }

                HStack {
                    Button("Cancel") {
                        onCancel()
                    }
                    .disabled(isSaving)

                    Spacer()

                    Button {
                        onSave()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.top, 8)
            }
            .padding(20)
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
            .shadow(radius: 12)
            .padding(24)
        }
    }
}

private struct BoardReorderSheet: View {
    @Binding var boards: [FrameAssetItem]
    @Binding var activeBoard: FrameAssetItem?
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 120), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Drag boards to reorder them.")
                        .font(.headline)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(boards) { board in
                            VStack(spacing: 8) {
                                Image(systemName: board.iconName)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text(board.displayLabel)
                                    .font(.subheadline.weight(.semibold))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .foregroundStyle(.primary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 90)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.secondary.opacity(0.12))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                            .opacity(activeBoard?.id == board.id ? 0.6 : 1)
                            .onDrag {
                                activeBoard = board
                                return NSItemProvider(
                                    item: board.id as NSString,
                                    typeIdentifier: UTType.text.identifier
                                )
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: BoardReorderDropDelegate(
                                    item: board,
                                    boards: $boards,
                                    activeBoard: $activeBoard
                                )
                            )
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Reorder Boards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct BoardReorderDropDelegate: DropDelegate {
    let item: FrameAssetItem
    @Binding var boards: [FrameAssetItem]
    @Binding var activeBoard: FrameAssetItem?

    func dropEntered(info: DropInfo) {
        guard let activeBoard, activeBoard != item else { return }
        guard let fromIndex = boards.firstIndex(of: activeBoard),
              let toIndex = boards.firstIndex(of: item)
        else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            boards.move(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
            )
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        activeBoard = nil
        return true
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
