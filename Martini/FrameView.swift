import SwiftUI
import AVKit
import UIKit
import Combine
import Foundation

@MainActor
struct FrameView: View {
    private let providedFrame: Frame
    @EnvironmentObject private var authService: AuthService
    @Environment(\.fullscreenMediaCoordinator) private var fullscreenCoordinator
    @State private var frame: Frame
    @Binding var assetOrder: [FrameAssetKind]
    let onClose: () -> Void
    let showsCloseButton: Bool
    let hasPreviousFrame: Bool
    let hasNextFrame: Bool
    let showsTopToolbar: Bool
    let activeFrameID: Frame.ID?
    let onNavigate: (FrameNavigationDirection) -> Void
    let onStatusSelected: (Frame, FrameStatus) -> Void
    @State private var selectedStatus: FrameStatus
    @State private var assetStack: [FrameAssetItem]
    @State private var visibleAssetID: FrameAssetItem.ID?
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
    @State private var isFrameVisible: Bool = false
    @State private var isCommentsVisible: Bool = false
    @State private var descriptionHeightRatio: CGFloat
    @State private var dragStartRatio: CGFloat?
    @State private var descriptionScrollOffset: CGFloat = 0
    @State private var isDraggingDescription: Bool = false
    @State private var isUpdatingStatus: Bool = false
    @State private var statusUpdateError: String?
    @State private var showingNoConnectionModal: Bool = false
    @State private var showingStatusSheet: Bool = false
    @State private var sheetVisible: Bool = false
    @State private var statusBeingUpdated: FrameStatus?
    @State private var showingScoutCamera: Bool = false
    @State private var showingScoutCameraWarning: Bool = false
    @State private var showingScoutCameraSettings: Bool = false
    @State private var showingAddBoardOptions: Bool = false
    @State private var showingSystemCamera: Bool = false
    @State private var showingUploadPicker: Bool = false
    @State private var capturedPhoto: CapturedPhoto?
    @State private var showingBoardRenameAlert: Bool = false
    @State private var boardRenameText: String = ""
    @State private var boardRenameTarget: FrameAssetItem?
    @State private var isRenamingBoard: Bool = false
    @State private var reorderBoards: [FrameAssetItem] = []
    @State private var activeReorderBoard: FrameAssetItem?
    @State private var isReorderingBoards: Bool = false
    @State private var reorderWiggle: Bool = false
    @State private var showingBoardDeleteAlert: Bool = false
    @State private var boardDeleteTarget: FrameAssetItem?
    @State private var boardActionError: String?
    @State private var isUploadingBoardAsset: Bool = false
    @State private var metadataSheetItem: BoardMetadataItem?
    @State private var boardPhotoAccessAlert: PhotoLibraryHelper.PhotoAccessAlert?
    @State private var descriptionAttributedText: NSAttributedString?
    @State private var showingDescriptionEditor: Bool = false
    @State private var descriptionEditorText: NSAttributedString = NSAttributedString(string: "")
    @State private var descriptionUpdateError: String?
    @State private var scriptNavigationTarget: ScriptNavigationTarget?
    @State private var didLogLayout: Bool = false
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    private let dimmerAnim = Animation.easeInOut(duration: 0.28)
    private let sheetAnim = Animation.spring(response: 0.42, dampingFraction: 0.92, blendDuration: 0.20)
    private let takePictureCardID = "take-picture"
    private let tabRowHeight: CGFloat = 100
    private let boardsTabsSpacing: CGFloat = 12
    private let selectionStore = ProjectKitSelectionStore.shared
    private let dataStore = LocalJSONStore.shared
    private let scriptPreviewFontSize = UIFont.preferredFont(forTextStyle: .body).pointSize
    private let uploadService = FrameUploadService()

    init(
        frame: Frame,
        assetOrder: Binding<[FrameAssetKind]>,
        onClose: @escaping () -> Void,
        showsCloseButton: Bool = true,
        hasPreviousFrame: Bool = false,
        hasNextFrame: Bool = false,
        showsTopToolbar: Bool = true,
        activeFrameID: Frame.ID? = nil,
        onNavigate: @escaping (FrameNavigationDirection) -> Void = { _ in },
        onStatusSelected: @escaping (Frame, FrameStatus) -> Void = { _, _ in }
    ) {
        providedFrame = frame
        _frame = State(initialValue: frame)
        _assetOrder = assetOrder
        self.onClose = onClose
        self.showsCloseButton = showsCloseButton
        self.hasPreviousFrame = hasPreviousFrame
        self.hasNextFrame = hasNextFrame
        self.showsTopToolbar = showsTopToolbar
        self.activeFrameID = activeFrameID
        self.onNavigate = onNavigate
        self.onStatusSelected = onStatusSelected
        _selectedStatus = State(initialValue: frame.statusEnum)

        let orderValue: [FrameAssetKind] = assetOrder.wrappedValue
        let initialStack: [FrameAssetItem] = FrameView.orderedAssets(for: frame, order: orderValue)
        _assetStack = State(initialValue: initialStack)
        let firstID: FrameAssetItem.ID? = initialStack.first?.id
        _visibleAssetID = State(initialValue: firstID)
        let initialMinDescriptionRatio = CreativeAspectRatioConfig.descriptionRatio(for: frame.creativeAspectRatio)
        _descriptionHeightRatio = State(initialValue: initialMinDescriptionRatio)
    }

    private var frameTitle: String {
        if frame.frameNumber > 0 {
            return "Frame \(frame.frameNumber)"
        }
        return "Frame"
    }

    private var systemCameraBoardLabel: String {
        switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            return "iPad Camera"
        default:
            return "iPhone Camera"
        }
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
            .fullScreenCover(item: $capturedPhoto) { currentPhoto in
                ScoutCameraReviewView(
                    image: currentPhoto.image,
                    frameLineConfigurations: [],
                    onImport: {
                        await importCapturedPhoto(currentPhoto.image)
                    },
                    onPrepareShare: {
                        currentPhoto.image
                    },
                    onRetake: {
                        capturedPhoto = nil
                        showingSystemCamera = true
                    },
                    onCancel: {
                        capturedPhoto = nil
                    }
                )
            }
            .navigationDestination(item: $scriptNavigationTarget) { target in
                ScriptView(targetDialogId: target.dialogId)
            }
            .sheet(item: $metadataSheetItem) { item in
                BoardMetadataSheet(item: item)
            }
            .fullScreenCover(isPresented: $showingSystemCamera) {
                MediaPicker(
                    sourceType: .camera,
                    allowsVideo: false,
                    onImagePicked: { image in
                        capturedPhoto = CapturedPhoto(image: image)
                    },
                    onVideoPicked: { _ in }
                )
            }
            .sheet(isPresented: $showingUploadPicker) {
                MediaPicker(
                    sourceType: .photoLibrary,
                    allowsVideo: true,
                    onImagePicked: { image in
                        Task { await uploadBoardImage(image, boardLabel: "Upload") }
                    },
                    onVideoPicked: { url in
                        Task { await uploadBoardVideo(url, boardLabel: "Upload") }
                    }
                )
            }
            .sheet(isPresented: $showingDescriptionEditor) {
                FrameDescriptionEditorSheet(
                    //title: "Edit \(frameTitle) Description",
                    title: "Edit Description",
                    initialText: descriptionEditorText,
                    onSave: { description in
                        let updatedFrame = try await authService.updateFrameDescription(
                            frameId: frame.id,
                            creativeId: frame.creativeId,
                            description: description
                        )
                        frame = updatedFrame
                    },
                    onError: { error in
                        descriptionUpdateError = error.localizedDescription
                    }
                )
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
            .overlay(alignment: .bottom) {
                statusSheetOverlay
            }
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
                if assetStack != newStack {
                    let previousStack = assetStack
                    assetStack = newStack
                    let previousIDs = Set(previousStack.map(\.id))
                    if let newBoard = newStack.first(where: { $0.kind == .board && !previousIDs.contains($0.id) }) {
                        visibleAssetID = newBoard.id
                    } else if visibleAssetID == nil {
                        visibleAssetID = newStack.first?.id
                    }
                }
            }
            .onReceive(authService.$frameUpdateEvent) { event in
                guard let event else { return }
                guard event.frameId == frame.id else { return }
                guard case .websocket(let eventName) = event.context else { return }
                switch eventName {
                case "update-clips":
                    Task {
                        await loadClips(force: true)
                    }
                case "comment-added":
                    guard isFrameVisible || isCommentsVisible else { return }
                    Task {
                        await loadComments(force: true)
                    }
                default:
                    break
                }
            }
            .onAppear {
                isFrameVisible = true
                refreshDescriptionAttributedText()
            }
            .onDisappear {
                isFrameVisible = false
            }
            .onChange(of: frame.description) { _ in
                refreshDescriptionAttributedText()
            }
            .onChange(of: colorScheme) { _ in
                refreshDescriptionAttributedText()
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
                    title: "Files for Frame \(frame.frameNumber)",
                    clips: $clips,
                    isLoading: $isLoadingClips,
                    errorMessage: $clipsError,
                    onReload: { await loadClips(force: true) },
                    onMediaPreview: { clip in
                        openClipPreview(clip)
                    }
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
            .alert(item: $boardPhotoAccessAlert) { alert in
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
                if showingAddBoardOptions {
                    AddBoardAlert(
                        onTakePhoto: {
                            showingAddBoardOptions = false
                            showingSystemCamera = true
                        },
                        onScoutCamera: {
                            showingAddBoardOptions = false
                            openScoutCamera()
                        },
                        onUpload: {
                            showingAddBoardOptions = false
                            showingUploadPicker = true
                        },
                        onCancel: {
                            showingAddBoardOptions = false
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
            .alert(
                "Unable to Update Description",
                isPresented: Binding(
                    get: { descriptionUpdateError != nil },
                    set: { if !$0 { descriptionUpdateError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { descriptionUpdateError = nil }
            } message: {
                Text(descriptionUpdateError ?? "An unknown error occurred.")
            }
            .overlay {
                MartiniAlertModal(
                    isPresented: $showingNoConnectionModal,
                    iconName: "wifi.exclamationmark",
                    iconColor: .red,
                    title: "No Connection",
                    message: "Martini can’t reach the server at the moment. You can keep working—markings are saved locally.\nOnce connection is restored, we’ll automatically push your updates and sync across all devices.",
                    actions: [
                        MartiniAlertAction(title: "CONTINUE OFFLINE", style: .primary) {
                            showingNoConnectionModal = false
                        }
                    ]
                )
            }
    }

    private var baseContent: some View {
        contentView
            .navigationTitle(frameTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsTopToolbar {
                    topToolbar
                }
                if shouldShowBottomToolbar {
                    bottomToolbar
                }
            }
            .overlay {
                if isUploadingBoardAsset {
                    ZStack {
                        Color.black.opacity(0.001)
                            .ignoresSafeArea()
                        uploadingBoardOverlay
                    }
                }
            }
    }

    private var uploadingBoardOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
            Text("Uploading")
                .font(.headline)
                .foregroundColor(.white)
        }
        .frame(width: 180, height: 180)
        .background(Color.black.opacity(0.8))
        .cornerRadius(20)
    }

    private var shouldShowBottomToolbar: Bool {
        guard let activeFrameID else { return true }
        return activeFrameID == frame.id
    }

    private var statusUpdateAlertBinding: Binding<Bool> {
        Binding(
            get: { statusUpdateError != nil },
            set: { if !$0 { statusUpdateError = nil } }
        )
    }

    @ToolbarContentBuilder
    private var topToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 2) {
                Text(frameTitle)
                    .font(.headline)
                if selectedStatus != .none {
                    Text(selectedStatus.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selectedStatus.markerBackgroundColor)
                        .textCase(.uppercase)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            )
                        )
                }
            }
            .animation(.easeInOut(duration: 0.2), value: selectedStatus)
        }

        if showsCloseButton {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Close")
            }
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
                CommentsView(
                    frameNumber: frame.frameNumber,
                    comments: comments,
                    isLoading: isLoadingComments,
                    errorMessage: commentsError,
                    isVisible: $isCommentsVisible,
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
                    .foregroundStyle(.martiniDefaultText)
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
            let portraitBoardsHeight: CGFloat = max(0, proxy.size.height - overlayHeight)
            let descriptionProgress: CGFloat = max(
                0,
                min(
                    1,
                    (descriptionHeightRatio - minDescriptionRatio) / (1 - minDescriptionRatio)
                )
            )
            let dimmerOpacity: CGFloat = descriptionProgress * 1
            let boardScale: CGFloat = 1 - (descriptionProgress * 0.04)
            let boardOpacity: CGFloat = max(0, 1 - descriptionProgress)

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
                        boardsSection(height: portraitBoardsHeight)
                            .scaleEffect(boardScale)
                            .opacity(boardOpacity)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                        Color(.systemBackground)
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
            .onAppear {
                guard !didLogLayout else { return }
                didLogLayout = true
                logFrameLayout(
                    containerSize: proxy.size,
                    isLandscape: isLandscape,
                    overlayHeight: overlayHeight,
                    portraitBoardsHeight: portraitBoardsHeight
                )
            }
        }
    }

    private var statusSheetOverlay: some View {
        ZStack(alignment: .bottom) {
            if showingStatusSheet {
                // Dimmer (gentle, native)
                Color(.systemBackground)
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
        let scrollerHeight = max(0, height - tabRowHeight - boardsTabsSpacing)

        return VStack(alignment: .leading, spacing: boardsTabsSpacing) {
            //Spacer()
            StackedAssetScroller(
                frame: frame,
                assetStack: assetStack,
                visibleAssetID: $visibleAssetID,
                primaryText: primaryText,
                takePictureID: takePictureCardID,
                takePictureAction: {
                    showingAddBoardOptions = true
                },
                onAssetTap: { asset in
                    guard asset.kind == .board else { return }
                    openBoardPreview(asset)
                },
                onMetadataTap: { asset, metadata in
                    metadataSheetItem = BoardMetadataItem(
                        boardName: asset.displayLabel,
                        metadata: metadata,
                        assetURL: asset.url,
                        assetIsVideo: asset.isVideo
                    )
                },
                contextMenuContent: { asset in
                    boardContextMenu(for: asset)
                }
            )
            .frame(height: scrollerHeight)

            //Spacer()
            boardCarouselTabs
            //Spacer()
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
                Button {
                    boardRenameTarget = asset
                    boardRenameText = asset.displayLabel
                    isRenamingBoard = false
                    showingBoardRenameAlert = true
                } label: {
                    Label("Rename", systemImage: "character.cursor.ibeam")
                }
                Button {
                    enterBoardReorderMode()
                } label: {
                    Label("Reorder", systemImage: "arrow.left.arrow.right")
                }
                Button {
                    pinBoard(asset)
                } label: {
                    Label("Pin board", systemImage: "pin.fill")
                }
                if asset.url != nil {
                    Button {
                        saveBoardAssetToPhotos(asset)
                    } label: {
                        Label(asset.isVideo ? "Download Video" : "Download Image", systemImage: "square.and.arrow.down")
                    }
                }
                Button(role: .destructive) {
                    boardDeleteTarget = asset
                    showingBoardDeleteAlert = true
                } label: {
                    Label("Delete", systemImage: "trash.fill")
                }
            } else {
                if asset.url != nil {
                    Button {
                        saveBoardAssetToPhotos(asset)
                    } label: {
                        Label(asset.isVideo ? "Download Video" : "Download Image", systemImage: "square.and.arrow.down")
                    }
                }
                Button(role: .destructive) {
                    boardDeleteTarget = asset
                    showingBoardDeleteAlert = true
                } label: {
                    Label("Delete", systemImage: "trash.fill")
                }
            }
        } else {
            EmptyView()
        }
    }

    private var secondaryText: String? {
        if let description: String = frame.description, !description.isEmpty { return description }
        return nil
    }

    private func refreshDescriptionAttributedText() {
        guard let secondaryText, !secondaryText.isEmpty else {
            descriptionAttributedText = nil
            return
        }

        let descriptionUIColor = UIColor(named: "MartiniDefaultDescriptionColor") ?? .label
        let attributedText = nsAttributedStringFromHTML(
            secondaryText,
            defaultColor: descriptionUIColor
        )

        descriptionAttributedText = attributedText
    }

    private var descriptionCopyText: String? {
        guard let description = secondaryText, !description.isEmpty else { return nil }
        return plainTextFromHTML(description)
    }

    private func openDescriptionEditor() {
        if let description = secondaryText, !description.isEmpty,
           let attributed = nsAttributedStringFromHTML(description) {
            descriptionEditorText = attributed
        } else if let description = secondaryText, !description.isEmpty {
            descriptionEditorText = NSAttributedString(string: plainTextFromHTML(description))
        } else {
            descriptionEditorText = NSAttributedString(string: "")
        }

        showingDescriptionEditor = true
    }

    @ViewBuilder
    private var descriptionSection: some View {
        if let secondaryText {
            VStack(alignment: .leading, spacing: 8) {
//                Text("Description")
//                    .font(.headline)
//                    .foregroundStyle(.primary)
                let scriptBlocks = ScriptParser.blocks(from: secondaryText, frameId: frame.id)
                let hasScriptMarkup = secondaryText.range(of: "qr-syntax", options: .caseInsensitive) != nil
                if hasScriptMarkup, scriptBlocks.contains(where: { $0.isDialog }) {
                    ScriptDescriptionPreview(blocks: scriptBlocks, fontSize: scriptPreviewFontSize) { dialogId in
                        scriptNavigationTarget = ScriptNavigationTarget(dialogId: dialogId)
                    }
                } else if let attributedText = descriptionAttributedText {
                    RichTextDisplayView(attributedText: attributedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(plainTextFromHTML(secondaryText))
                        .font(.body)
                        .foregroundStyle(Color.martiniDefaultDescriptionColor)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 20)
//            .contextMenu {
//                Button {
//                    UIPasteboard.general.string = descriptionCopyText ?? ""
//                } label: {
//                    Label("Copy Description", systemImage: "doc.on.doc")
//                }
//                Button {
//                    openDescriptionEditor()
//                } label: {
//                    Label("Edit Description", systemImage: "pencil")
//                }
//            }
            .disabled(secondaryText.isEmpty)
        } else {
            VStack {
//                Text("Description")
//                    .font(.headline)
//                    .foregroundStyle(.primary)

                Image(systemName: "character.cursor.ibeam")
                    .font(.system(size: 48, weight: .regular))
                    .foregroundStyle(Color.martiniDefaultDescriptionColor)
                    .opacity(0.3)
            }
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .center)
            .padding(.top, 20)
            .contextMenu {
                Button {
                    openDescriptionEditor()
                } label: {
                    Label("Edit Description", systemImage: "pencil")
                }
            }
        }
    }

    private struct ScriptNavigationTarget: Identifiable, Hashable {
        let id = UUID()
        let dialogId: String
    }

    private var frameTagGroups: [FrameTagGroup] {
        guard let tags = frame.tags, !tags.isEmpty else { return [] }

        let grouped = Dictionary(grouping: tags) { tag -> String in
            let group = tag.groupName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (group?.isEmpty == false ? group : nil) ?? "Tags"
        }

        return grouped.map { key, tags in
            FrameTagGroup(
                id: key,
                name: key,
                tags: Array(Set(tags)).sorted { $0.name.lowercased() < $1.name.lowercased() }
            )
        }
        .sorted { lhs, rhs in
            if lhs.name == "Tags" { return true }
            if rhs.name == "Tags" { return false }
            return lhs.name.lowercased() < rhs.name.lowercased()
        }
    }

    private func tagGroupColor(for groupName: String) -> Color {
        let normalized = groupName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let resolvedColorValue = tagGroupColorValue(for: normalized)

        if let resolved = colorFromTagGroupValue(resolvedColorValue) {
            print("[TagPill] groupName='\(groupName)' normalized='\(normalized)' resolved='\(resolvedColorValue)' color=custom")
            return resolved
        }

        let colorName: String
        let color: Color

        switch resolvedColorValue {
        case "blue":
            colorName = "martiniBlueColor"
            color = .martiniBlueColor
        case "cyan":
            colorName = "martiniCyanColor"
            color = .martiniCyanColor
        case "green":
            colorName = "martiniGreenColor"
            color = .martiniGreenColor
        case "lime":
            colorName = "martiniLimeColor"
            color = .martiniLimeColor
        case "orange":
            colorName = "martiniOrangeColor"
            color = .martiniOrangeColor
        case "pink":
            colorName = "martiniPinkColor"
            color = .martiniPinkColor
        case "purple":
            colorName = "martiniPurpleColor"
            color = .martiniPurpleColor
        case "red":
            colorName = "martiniRedColor"
            color = .martiniRedColor
        case "yellow":
            colorName = "martiniYellowColor"
            color = .martiniYellowColor
        default:
            colorName = "martiniGrayColor"
            color = .martiniGrayColor
        }

        //print("[TagPill] groupName='\(groupName)' normalized='\(normalized)' resolved='\(resolvedColorValue)' color=\(colorName)")
        return color
    }

    private func tagGroupColorValue(for normalizedGroupName: String) -> String {
        let matchedGroup = authService.tagGroups.first {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedGroupName
        }

        let rawColor = matchedGroup?.color?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return rawColor?.isEmpty == false ? rawColor! : normalizedGroupName
    }

    private func colorFromTagGroupValue(_ value: String) -> Color? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else { return nil }

        let hexString = cleaned.hasPrefix("#") ? String(cleaned.dropFirst()) : cleaned
        guard hexString.count == 6 || hexString.count == 8 else { return nil }
        guard hexString.range(of: "^[0-9a-f]+$", options: .regularExpression) != nil else { return nil }

        var hexNumber: UInt64 = 0
        guard Scanner(string: hexString).scanHexInt64(&hexNumber) else { return nil }

        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        if hexString.count == 8 {
            red = Double((hexNumber & 0xFF000000) >> 24) / 255
            green = Double((hexNumber & 0x00FF0000) >> 16) / 255
            blue = Double((hexNumber & 0x0000FF00) >> 8) / 255
            alpha = Double(hexNumber & 0x000000FF) / 255
        } else {
            red = Double((hexNumber & 0xFF0000) >> 16) / 255
            green = Double((hexNumber & 0x00FF00) >> 8) / 255
            blue = Double(hexNumber & 0x0000FF) / 255
            alpha = 1.0
        }

        return Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    @ViewBuilder
    private var tagsSection: some View {
        if frameTagGroups.isEmpty {
            EmptyView()
        } else {
            let pillTextColor = Color(
                red: colorScheme == .dark ? 243.0 / 255.0 : 15.0 / 255.0,
                green: colorScheme == .dark ? 244.0 / 255.0 : 23.0 / 255.0,
                blue: colorScheme == .dark ? 246.0 / 255.0 : 42.0 / 255.0
            )
            let tagItems = frameTagGroups.enumerated().flatMap { groupIndex, group in
                var items: [TagFlowItem] = []
                if frameTagGroups.count > 1 {
                    items.append(
                        TagFlowItem(
                            id: "group-\(groupIndex)-\(group.name)",
                            kind: .groupLabel(group.name)
                        )
                    )
                }
                for (tagIndex, tag) in group.tags.enumerated() {
                    let tagId = tag.id ?? tag.name
                    items.append(
                        TagFlowItem(
                            id: "tag-\(groupIndex)-\(tagIndex)-\(tagId)",
                            kind: .tag(tag, groupName: group.name)
                        )
                    )
                }
                return items
            }
            VStack(alignment: .leading, spacing: 20) {
                Divider()
//                Text("Tags")
//                    .font(.headline)

                TagFlowLayout(spacing: 8) {
                    ForEach(tagItems) { item in
                        switch item.kind {
                        case .groupLabel:
                            EmptyView()

                        case .tag(let tag, let groupName):
                            Text(tag.name)
                                //.foregroundColor(pillTextColor)
                                .foregroundColor(tagGroupColor(for: groupName))
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule().fill(tagGroupColor(for: groupName)).opacity(0.2)
                                )
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func descriptionOverlay(containerHeight: CGFloat, overlayHeight: CGFloat, allowsExpansion: Bool) -> some View {
        VStack(spacing: 10) {
            if allowsExpansion {
                descriptionHandle
                    .gesture(descriptionDragGesture(containerHeight: containerHeight))
                    .onTapGesture {
                        toggleDescriptionExpanded()
                    }
            } else {
                Color.clear
                    .frame(height: 10)
                    .frame(maxWidth: .infinity)
            }

            ScrollView(.vertical, showsIndicators: true) {
                let contentStack = VStack(alignment: .leading, spacing: 16) {
                    descriptionSection
                        .padding(.horizontal, 20)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard allowsExpansion else { return }
                            toggleDescriptionExpanded()
                        }

                    if !allowsExpansion || isDescriptionExpanded {
                        tagsSection
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                    } else {
                        Color.clear
                            .frame(height: 24)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Group {
                    if allowsExpansion {
                        contentStack
                    } else {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            contentStack
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: overlayHeight)
                    }
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: DescriptionScrollOffsetKey.self, value: proxy.frame(in: .named("descriptionScroll")).minY)
                    }
                )
            }
            .coordinateSpace(name: "descriptionScroll")
            .scrollDisabled(allowsExpansion ? !isDescriptionExpanded || isDraggingDescription : false)
            .onPreferenceChange(DescriptionScrollOffsetKey.self) { offset in
                descriptionScrollOffset = offset
                handleDescriptionScroll(offset: offset)
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.descriptionBackground).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            .contextMenu {
                Button {
                    UIPasteboard.general.string = descriptionCopyText ?? ""
                } label: {
                    Label("Copy Description", systemImage: "doc.on.doc")
                }
                Button {
                    openDescriptionEditor()
                } label: {
                    Label("Edit Description", systemImage: "pencil")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: overlayHeight)
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    private var descriptionHandle: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.3))
                .frame(width: 44, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
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
            GeometryReader { geo in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if isReorderingBoards {
                                    commitBoardReorder()
                                }
                            }

                        HStack(spacing: 8) {
                            if isReorderingBoards {
                                ForEach(reorderBoards) { board in
                                    let isPinned = boardEntry(for: board)?.isPinned == true
                                    let rotation: Double = reorderWiggle ? 1.5 : -1.5

                                    Group {
                                        if isPinned {
                                            reorderLabel(for: board, isPinned: isPinned)
                                        } else {
                                            reorderLabel(for: board, isPinned: isPinned)
                                                .onDrag {
                                                    activeReorderBoard = board
                                                    return NSItemProvider(
                                                        item: board.id as NSString,
                                                        typeIdentifier: UTType.text.identifier
                                                    )
                                                }
                                        }
                                    }
                                    .rotationEffect(.degrees(isPinned ? 0 : rotation))
                                    .animation(
                                        isPinned ? .default
                                        : .easeInOut(duration: 0.12).repeatForever(autoreverses: true),
                                        value: reorderWiggle
                                    )
                                    .opacity(activeReorderBoard?.id == board.id ? 0.6 : 1)
                                    .onDrop(
                                        of: [UTType.text],
                                        delegate: BoardReorderDropDelegate(
                                            item: board,
                                            boards: $reorderBoards,
                                            activeBoard: $activeReorderBoard,
                                            pinnedBoardId: pinnedBoardId
                                        )
                                    )
                                    .id(board.id)
                                }

                                Button {
                                    cancelBoardReorder()
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .padding(10)
                                        .background(
                                            Capsule()
                                                .fill(Color.secondary.opacity(0.15))
                                        )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    commitBoardReorder()
                                } label: {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.martiniDefaultTextColor)
                                        .padding(10)
                                        .background(
                                            Capsule()
                                                .fill(Color.martiniDefaultColor)
                                        )
                                }
                                .buttonStyle(.plain)
                            } else {
                                ForEach(assetStack) { asset in
                                    let isSelected: Bool = (asset.id == visibleAssetID)
                                    let isPinned = boardEntry(for: asset)?.isPinned == true

                                    Button {
                                        visibleAssetID = asset.id
                                    } label: {
                                        tabLabel(for: asset, isPinned: isPinned, isSelected: isSelected)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        boardContextMenu(for: asset)
                                    }
                                    .id(asset.id)
                                }

                                Button {
                                    showingAddBoardOptions = true
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .padding(10)
                                        .background(
                                            Capsule()
                                                .fill(Color.secondary.opacity(0.15))
                                        )
                                }
                                .buttonStyle(.plain)
                                .id(takePictureCardID)
                            }
                        }

                        Spacer(minLength: 0)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if isReorderingBoards {
                                    commitBoardReorder()
                                }
                            }
                    }
                    .padding(.horizontal, 20)
                    // Force content to be at least viewport width so Spacers can center it
                    .frame(minWidth: geo.size.width, alignment: .center)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .scrollTargetLayout()
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
                // iOS 17+ onChange API (two params)
                .onChange(of: visibleAssetID) { _, newValue in
                    guard let id = newValue else { return }
                    withAnimation(.snappy(duration: 0.25)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
                .onAppear {
                    guard let id = visibleAssetID else { return }
                    proxy.scrollTo(id, anchor: .center)
                }
                // iOS 17+ onChange API (two params)
                .onChange(of: isReorderingBoards) { _, isReordering in
                    if isReordering {
                        reorderWiggle.toggle()
                    } else {
                        reorderWiggle = false
                    }
                }
            }
            // Give GeometryReader a deterministic height (match your tab row height)
            .frame(height: tabRowHeight)
        }
    }


    private var pinnedBoardId: String? {
        frame.boards?.first(where: { $0.isPinned })?.id
    }

    @ViewBuilder
    private func tabLabel(for asset: FrameAssetItem, isPinned: Bool, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            if isPinned && asset.kind == .board {
                Image(systemName: "pin.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
            Text(asset.label ?? asset.kind.displayName)
        }
        .font(.system(size: 14, weight: .semibold))
        //.foregroundStyle(isSelected ? Color.white : Color.primary)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minWidth: 80)
        .background(
            Capsule()
                .fill(isSelected ? Color.martiniDefaultColor : Color.secondary.opacity(0.2))
        )
        .foregroundStyle(isSelected ? Color.martiniDefaultText : Color.primary)
    }

    private func reorderLabel(for board: FrameAssetItem, isPinned: Bool) -> some View {
        HStack(spacing: 6) {
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
            Text(board.displayLabel)
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(Color.primary)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minWidth: 80)
        .background(
            Capsule()
                .fill(Color.secondary.opacity(0.15))
        )
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
            if Task.isCancelled {
                return
            }
            if let urlError = error as? URLError, urlError.code == .cancelled {
                return
            }
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
                let updateResult = try await authService.updateFrameStatus(id: frame.id, to: status)
                triggerStatusHaptic(for: status)

                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedStatus = updateResult.frame.statusEnum
                    }

                    frame = updateResult.frame
                    onStatusSelected(updateResult.frame, updateResult.frame.statusEnum)
                    closeStatusSheet()

                    if updateResult.wasQueued {
                        showingNoConnectionModal = true
                    }
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

    private func importCapturedPhoto(_ image: UIImage) async {
        let didUpload = await uploadBoardImage(image, boardLabel: systemCameraBoardLabel)
        if didUpload {
            capturedPhoto = nil
        }
    }

    private func uploadBoardImage(_ image: UIImage, boardLabel: String) async -> Bool {
        guard let projectId = authService.projectId else {
            boardActionError = "Missing project ID for upload."
            return false
        }
        guard let data = compressedImageData(from: image, maxPixelDimension: 2000) else {
            boardActionError = "Failed to compress image."
            return false
        }
        isUploadingBoardAsset = true
        defer { isUploadingBoardAsset = false }
        do {
            try await uploadService.uploadBoardAsset(
                data: data,
                filename: "photoboard.jpg",
                mimeType: "image/jpeg",
                boardLabel: boardLabel,
                shootId: projectId,
                creativeId: frame.creativeId,
                frameId: frame.id,
                bearerToken: authService.currentBearerToken(),
                metadata: nil
            )
            return true
        } catch {
            boardActionError = error.localizedDescription
            return false
        }
    }

    private func uploadBoardVideo(_ sourceURL: URL, boardLabel: String) async -> Bool {
        guard let projectId = authService.projectId else {
            boardActionError = "Missing project ID for upload."
            return false
        }
        isUploadingBoardAsset = true
        defer { isUploadingBoardAsset = false }
        do {
            let compressedURL = try await compressVideoForUpload(sourceURL: sourceURL)
            let data = try Data(contentsOf: compressedURL)
            try await uploadService.uploadBoardAsset(
                data: data,
                filename: "board.mp4",
                mimeType: "video/mp4",
                boardLabel: boardLabel,
                shootId: projectId,
                creativeId: frame.creativeId,
                frameId: frame.id,
                bearerToken: authService.currentBearerToken(),
                metadata: nil
            )
            return true
        } catch {
            boardActionError = error.localizedDescription
            return false
        }
    }

    private func compressedImageData(from image: UIImage, maxPixelDimension: CGFloat) -> Data? {
        let resized = resizedImageForUpload(from: image, maxPixelDimension: maxPixelDimension)
        return resized.jpegData(compressionQuality: 0.85)
    }

    private func resizedImageForUpload(from image: UIImage, maxPixelDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxDimension = max(size.width, size.height)
        guard maxDimension > maxPixelDimension else { return image }

        let scale = maxPixelDimension / maxDimension
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private func compressVideoForUpload(sourceURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080) else {
            throw NSError(domain: "VideoExport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create export session."])
        }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        return try await withCheckedThrowingContinuation { continuation in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    continuation.resume(returning: outputURL)
                case .failed, .cancelled:
                    continuation.resume(throwing: exportSession.error ?? NSError(domain: "VideoExport", code: 2, userInfo: nil))
                default:
                    break
                }
            }
        }
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
    private var minDescriptionRatio: CGFloat {
        CreativeAspectRatioConfig.descriptionRatio(for: frame.creativeAspectRatio)
    }

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

    private func logFrameLayout(
        containerSize: CGSize,
        isLandscape: Bool,
        overlayHeight: CGFloat,
        portraitBoardsHeight: CGFloat
    ) {
        let aspectRatioText = frame.creativeAspectRatio ?? "nil"
        let parsedAspectRatio = String(format: "%.3f", frameAspectRatio)

        if isLandscape {
            let boardsSize = CGSize(width: containerSize.width * 0.6, height: containerSize.height)
            let descriptionSize = CGSize(width: containerSize.width * 0.4, height: containerSize.height)
            print("[FrameView] aspectRatio=\(aspectRatioText) parsed=\(parsedAspectRatio) layout=landscape boardsSize=\(formatSize(boardsSize)) descriptionSize=\(formatSize(descriptionSize))")
        } else {
            let boardsSize = CGSize(width: containerSize.width, height: portraitBoardsHeight)
            let descriptionSize = CGSize(width: containerSize.width, height: overlayHeight)
            print("[FrameView] aspectRatio=\(aspectRatioText) parsed=\(parsedAspectRatio) layout=portrait boardsSize=\(formatSize(boardsSize)) descriptionSize=\(formatSize(descriptionSize))")
        }
    }

    private func formatSize(_ size: CGSize) -> String {
        String(format: "%.1f x %.1f", size.width, size.height)
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

    private func enterBoardReorderMode() {
        reorderBoards = boardEntries()
        activeReorderBoard = nil
        isReorderingBoards = true
    }

    private func cancelBoardReorder() {
        reorderBoards = boardEntries()
        activeReorderBoard = nil
        isReorderingBoards = false
    }

    private func commitBoardReorder() {
        saveBoardReorder()
        isReorderingBoards = false
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

        let fallbackLabel = asset.displayLabel
        Task {
            do {
                try await authService.removeBoardImage(frameId: frame.id, boardLabel: fallbackLabel)
                boardDeleteTarget = nil
            } catch {
                boardActionError = error.localizedDescription
            }
        }
    }

    private func saveBoardAssetToPhotos(_ asset: FrameAssetItem) {
        guard let url = asset.url else { return }
        Task {
            do {
                let (downloadedURL, _) = try await URLSession.shared.download(from: url)
                let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: downloadedURL, to: destinationURL)

                let result: PhotoSaveResult
                if asset.isVideo {
                    result = await PhotoLibraryHelper.saveVideo(url: destinationURL)
                } else {
                    let data = try Data(contentsOf: destinationURL)
                    result = await PhotoLibraryHelper.saveImage(data: data)
                }

                if case .accessDenied = result {
                    boardPhotoAccessAlert = PhotoLibraryHelper.PhotoAccessAlert(
                        message: PhotoLibraryHelper.accessDeniedMessage(for: .board)
                    )
                }
            } catch {
                print("Failed to save board to Photos: \(error)")
            }
        }
    }

    private func totalCommentCount(in comments: [Comment]) -> Int {
        comments.reduce(0) { partial, comment in
            partial + 1 + totalCommentCount(in: comment.replies)
        }
    }

    private func metadataForAsset(_ asset: FrameAssetItem) -> JSONValue? {
        guard asset.kind == .board else { return nil }
        guard let metadata = frame.boards?.first(where: { $0.id == asset.id })?.metadata else {
            return nil
        }
        if case .null = metadata {
            return nil
        }
        return metadata
    }

    private func openBoardPreview(_ asset: FrameAssetItem) {
        guard let url = asset.url else { return }
        let media: MediaItem = asset.isVideo ? .videoURL(url) : .imageURL(url)
        let metadataItem = metadataForAsset(asset).map { metadata in
            BoardMetadataItem(
                boardName: asset.displayLabel,
                metadata: metadata,
                assetURL: asset.url,
                assetIsVideo: asset.isVideo
            )
        }
        fullscreenCoordinator?.configuration = FullscreenMediaConfiguration(
            media: media,
            config: .default,
            metadataItem: metadataItem,
            thumbnailURL: asset.thumbnailURL
        )
    }

    private func openClipPreview(_ clip: Clip) {
        guard let url = clip.fileURL else { return }
        let media: MediaItem = clip.isVideo ? .videoURL(url) : .imageURL(url)
        fullscreenCoordinator?.configuration = FullscreenMediaConfiguration(
            media: media,
            config: .default,
            metadataItem: nil,
            thumbnailURL: clip.thumbnailURL
        )
    }

    private func descriptionDragGesture(containerHeight: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard canDragDescription else { return }
                if dragStartRatio == nil {
                    let handleHitAreaHeight: CGFloat = 60
                    guard descriptionScrollOffset >= 0,
                          value.startLocation.y <= handleHitAreaHeight else {
                        return
                    }
                    isDraggingDescription = true
                    dragStartRatio = descriptionHeightRatio
                }
                guard isDraggingDescription else { return }

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

    private func toggleDescriptionExpanded() {
        setDescriptionExpanded(!isDescriptionExpanded)
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



private struct FrameTagGroup: Identifiable {
    let id: String
    let name: String
    let tags: [FrameTag]
}

private struct TagFlowItem: Identifiable {
    let id: String
    let kind: Kind

    enum Kind {
        case groupLabel(String)
        case tag(FrameTag, groupName: String)
    }
}

private struct TagFlowLayout: Layout {
    let spacing: CGFloat

    init(spacing: CGFloat) {
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        let layout = layoutRows(maxWidth: maxWidth, subviews: subviews)
        let totalHeight = layout.rows.reduce(0) { $0 + $1.height } + spacing * max(0, CGFloat(layout.rows.count - 1))
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = layoutRows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY

        for row in layout.rows {
            var x = bounds.minX
            for index in row.indices {
                let subview = subviews[index]
                let size = layout.sizes[index]
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func layoutRows(maxWidth: CGFloat, subviews: Subviews) -> (rows: [Row], sizes: [CGSize]) {
        var rows: [Row] = []
        var currentRow = Row()
        var sizes: [CGSize] = Array(repeating: .zero, count: subviews.count)

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            sizes[index] = size

            if currentRow.indices.isEmpty {
                currentRow.indices.append(index)
                currentRow.width = size.width
                currentRow.height = max(currentRow.height, size.height)
                continue
            }

            let candidateWidth = currentRow.width + spacing + size.width
            if candidateWidth <= maxWidth {
                currentRow.indices.append(index)
                currentRow.width = candidateWidth
                currentRow.height = max(currentRow.height, size.height)
            } else {
                rows.append(currentRow)
                currentRow = Row(indices: [index], width: size.width, height: size.height)
            }
        }

        if !currentRow.indices.isEmpty {
            rows.append(currentRow)
        }

        return (rows, sizes)
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
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
    let onAssetTap: ((FrameAssetItem) -> Void)?
    let onMetadataTap: ((FrameAssetItem, JSONValue) -> Void)?
    let contextMenuContent: (FrameAssetItem) -> ContextMenuContent

    var body: some View {
        GeometryReader { proxy in
            let cardWidth: CGFloat = proxy.size.width * 0.82
            let idealHeight: CGFloat = cardWidth * 1.15
            let availableHeight: CGFloat = proxy.size.height
            let cardHeight: CGFloat = min(idealHeight, availableHeight)
            let cardCornerRadius: CGFloat = 16
            let aspectRatio: CGFloat = FrameLayout.aspectRatio(from: frame.creativeAspectRatio ?? "") ?? (16.0 / 9.0)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .center, spacing: 0) {
                    ForEach(assetStack) { asset in
                        let shouldEnablePreview = asset.kind == .preview
                        let shouldHandleTap = asset.kind == .board
                        let metadata = metadataForAsset(asset)
                        AssetCardView(
                            frame: frame,
                            asset: asset,
                            cardWidth: cardWidth,
                            primaryText: primaryText,
                            enablesFullScreen: shouldEnablePreview,
                            showMetadataOverlay: metadata != nil,
                            onMetadataTap: {
                                if let metadata {
                                    onMetadataTap?(asset, metadata)
                                }
                            },
                            onTap: shouldHandleTap ? {
                                onAssetTap?(asset)
                            } : nil
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            //.background(Color(.black))
        }
    }

    private func metadataForAsset(_ asset: FrameAssetItem) -> JSONValue? {
        guard asset.kind == .board else { return nil }
        guard let metadata = frame.boards?.first(where: { $0.id == asset.id })?.metadata else {
            return nil
        }
        if case .null = metadata {
            return nil
        }
        return metadata
    }
}

private struct AssetCardView: View {
    let frame: Frame
    let asset: FrameAssetItem
    let cardWidth: CGFloat
    let primaryText: String?
    let enablesFullScreen: Bool
    let showMetadataOverlay: Bool
    let onMetadataTap: (() -> Void)?
    let onTap: (() -> Void)?
    private let cardCornerRadius: CGFloat = 16

    var body: some View {
        let card = FrameLayout(
            frame: frame,
            primaryAsset: asset,
            title: primaryText,
            showStatusBadge: true,
            showFrameNumberOverlay: true,
            showMetadataOverlay: showMetadataOverlay,
            metadataTapAction: onMetadataTap,
            showTextBlock: false,
            cornerRadius: cardCornerRadius,
            enablesFullScreen: enablesFullScreen
        )

        let styledCard = card
            .frame(width: cardWidth)
            .padding(.vertical, 16)
            .applyHorizontalScrollTransition()
            //.shadow(radius: 10, x: 0, y: 10)

        if let onTap {
            styledCard
                .onTapGesture {
                    onTap()
                }
        } else {
            styledCard
        }
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
                    Image(systemName: "plus")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(Color.primary)
                    Text("Add Board")
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                }
            }
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(width: cardWidth)
            .padding(.vertical, 16)
            //.shadow(radius: 10, x: 0, y: 10)
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

private struct AddBoardAlert: View {
    let onTakePhoto: () -> Void
    let onScoutCamera: () -> Void
    let onUpload: () -> Void
    let onCancel: () -> Void
    @State private var isExpanded: Bool = false

    private let backgroundFade = Animation.easeInOut(duration: 0.2)
    private let buttonPop = Animation.spring(response: 0.25, dampingFraction: 0.5, blendDuration: 0.3)
    private let buttonSpacing: CGFloat = 0

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .opacity(isExpanded ? 0.4 : 0)
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }
                .animation(backgroundFade, value: isExpanded)
            
            VStack(spacing: 20) {
                
                Text("Add Board")
                    .font(.title3.weight(.semibold))
                
                GlassEffectContainer(spacing: 20.0) {
                    
                    
                    HStack(spacing: 20) {
                        actionButton(title: "Take Photo", systemImage: "camera") {
                            onTakePhoto()
                        }
                        .offset(x: isExpanded ? buttonSpacing : 80)
                        .opacity(isExpanded ? 1 : 0)
                        .scaleEffect(isExpanded ? 1 : 0.88)
                        .animation(buttonPop.delay(0.15), value: isExpanded)
                        
                        actionButton(title: "Scout Camera", systemImage: "camera.viewfinder") {
                            onScoutCamera()
                        }
                        .opacity(isExpanded ? 1 : 0)
                        .scaleEffect(isExpanded ? 1 : 0.88)
                        .animation(buttonPop.delay(0.15), value: isExpanded)
                        
                        actionButton(title: "Upload", systemImage: "square.and.arrow.up") {
                            onUpload()
                        }
                        .offset(x: isExpanded ? buttonSpacing : -80)
                        .opacity(isExpanded ? 1 : 0)
                        .scaleEffect(isExpanded ? 1 : 0.88)
                        .animation(buttonPop.delay(0.15), value: isExpanded)
                    }
                    
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .clipShape(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            // 👇 POP IN ANIMATION ON THE WHOLE BOX
            .opacity(isExpanded ? 1 : 0)
            .scaleEffect(isExpanded ? 1 : 0.6)
            //.offset(y: isExpanded ? 0 : 18)
            .blur(radius: isExpanded ? 0 : 6)
            .animation(.spring(response: 0.34, dampingFraction: 0.82), value: isExpanded)
        }
        .onAppear {
            withAnimation(buttonPop) {
                isExpanded = true
            }
        }
        .onDisappear {
            isExpanded = false
        }
    }

    @ViewBuilder
    private func actionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    Image(systemName: systemImage)
                        .font(.system(size: 30, weight: .light))
                        //.symbolEffect(.drawOn.byLayer, options: .nonRepeating)
                }
                .frame(width: 80, height: 80)
                .foregroundColor(.primary)
                .glassEffect(.regular.interactive())
                
                Text(title)
                    .font(.caption)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct BoardReorderDropDelegate: DropDelegate {
    let item: FrameAssetItem
    @Binding var boards: [FrameAssetItem]
    @Binding var activeBoard: FrameAssetItem?
    let pinnedBoardId: String?

    func dropEntered(info: DropInfo) {
        guard let activeBoard, activeBoard != item else { return }
        guard activeBoard.id != pinnedBoardId else { return }
        guard let fromIndex = boards.firstIndex(of: activeBoard),
              let toIndex = boards.firstIndex(of: item)
        else { return }

        if let pinnedBoardId,
           let pinnedIndex = boards.firstIndex(where: { $0.id == pinnedBoardId }),
           toIndex <= pinnedIndex {
            return
        }

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

private struct MediaPicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let allowsVideo: Bool
    let onImagePicked: (UIImage) -> Void
    let onVideoPicked: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = RotatingImagePickerController()
        picker.delegate = context.coordinator
        if UIImagePickerController.isSourceTypeAvailable(sourceType) {
            picker.sourceType = sourceType
        } else {
            picker.sourceType = .photoLibrary
        }
        if allowsVideo {
            picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        } else {
            picker.mediaTypes = [UTType.image.identifier]
        }
        picker.allowsEditing = false
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: MediaPicker

        init(parent: MediaPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            defer { parent.dismiss() }
            if let mediaType = info[.mediaType] as? String {
                if mediaType == UTType.image.identifier {
                    if let image = info[.originalImage] as? UIImage {
                        parent.onImagePicked(image)
                    }
                } else if mediaType == UTType.movie.identifier {
                    if let url = info[.mediaURL] as? URL {
                        parent.onVideoPicked(url)
                    }
                }
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

private struct CapturedPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}

private final class RotatingImagePickerController: UIImagePickerController {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .all
    }

    override var shouldAutorotate: Bool {
        true
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.view.frame = CGRect(origin: .zero, size: size)
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        })
    }
}
//
//#Preview {
//    let sample = Frame(
//        id: "1",
//        creativeId: "c1",
//        board: "https://example.com/board.jpg",
//        frameOrder: "1",
//        photoboard: "https://example.com/board.jpg",
//        preview: "https://example.com/preview.mp4",
//        previewThumb: "https://example.com/preview_thumb.jpg",
//        description: "A sample description.",
//        caption: "Sample Caption",
//        status: FrameStatus.inProgress.rawValue
//    )
//    FrameView(frame: sample, assetOrder: .constant([.board, .preview])) {}
//}
