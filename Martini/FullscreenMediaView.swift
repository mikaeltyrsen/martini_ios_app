import AVFoundation
import AVKit
import ImageIO
import PencilKit
import SwiftUI

enum MediaItem: Equatable {
    case imageURL(URL)
    case videoURL(URL)

    var url: URL {
        switch self {
        case .imageURL(let url), .videoURL(let url):
            return url
        }
    }

    var isVideo: Bool {
        if case .videoURL = self {
            return true
        }
        return false
    }
}

struct MediaViewerConfig: Equatable {
    // UI
    var showsTopToolbar: Bool = true
    var tapTogglesChrome: Bool = true

    // VIDEO UI controls
    var showsVideoControls: Bool = true
    var showsPlayButtonOverlay: Bool = true
    var allowPiP: Bool = false

    // VIDEO playback behavior
    var autoplay: Bool = true
    var loop: Bool = false
    var startMuted: Bool = false
    var audioEnabled: Bool = true

    static let `default` = MediaViewerConfig()
}

struct FullscreenMediaViewer: View {
    @Binding var isPresented: Bool
    let media: MediaItem
    let config: MediaViewerConfig
    let metadataItem: BoardMetadataItem?
    let thumbnailURL: URL?
    let markupConfiguration: BoardMarkupConfiguration?
    let startsInMarkupMode: Bool

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @EnvironmentObject private var authService: AuthService

    @State private var isVisible: Bool = false
    @State private var isToolbarVisible: Bool
    @State private var isMetadataOverlayVisible: Bool
    @State private var isMarkupMode: Bool
    @State private var markupDrawing: PKDrawing
    @State private var isToolPickerVisible: Bool
    @State private var showMarkupOverlay: Bool
    @State private var showsDiscardMarkupAlert: Bool = false
    @State private var showsClearMarkupAlert: Bool = false
    @State private var mediaAspectRatio: CGFloat?
    @State private var mediaPixelSize: CGSize?
    @State private var hasLoadedFullImage: Bool = false
    @State private var isMapSheetPresented: Bool = false
    @State private var markupCanvasSize: CGSize = .zero
    @State private var hasScaledInitialDrawing: Bool = false
    @AppStorage("scoutCameraFullscreenShowFrameLines") private var showFrameLines: Bool = true
    @AppStorage("scoutCameraFullscreenShowFrameShading") private var showFrameShading: Bool = true
    @AppStorage("scoutCameraFullscreenShowCrosshair") private var showCrosshair: Bool = true
    @AppStorage("scoutCameraFullscreenShowGrid") private var showGrid: Bool = true

    private let animationDuration: Double = 0.25

    private var isCompactPortrait: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .regular
    }

    init(
        isPresented: Binding<Bool>,
        media: MediaItem,
        config: MediaViewerConfig = .default,
        metadataItem: BoardMetadataItem? = nil,
        thumbnailURL: URL? = nil,
        markupConfiguration: BoardMarkupConfiguration? = nil,
        startsInMarkupMode: Bool = false
    ) {
        _isPresented = isPresented
        self.media = media
        self.config = config
        self.metadataItem = metadataItem
        self.thumbnailURL = thumbnailURL
        self.markupConfiguration = markupConfiguration
        self.startsInMarkupMode = startsInMarkupMode
        let shouldStartMarkup = startsInMarkupMode && markupConfiguration != nil && !media.isVideo
        let hasInitialMarkup = !(markupConfiguration?.initialDrawing.strokes.isEmpty ?? true)
        _isToolbarVisible = State(initialValue: config.showsTopToolbar)
        _isMetadataOverlayVisible = State(initialValue: metadataItem != nil && config.showsTopToolbar && !shouldStartMarkup)
        _isMarkupMode = State(initialValue: shouldStartMarkup)
        _markupDrawing = State(initialValue: markupConfiguration?.initialDrawing ?? PKDrawing())
        _isToolPickerVisible = State(initialValue: shouldStartMarkup)
        _showMarkupOverlay = State(initialValue: hasInitialMarkup)
    }

    var body: some View {
        GeometryReader { proxy in
            let mediaSize = aspectFitSize(
                in: proxy.size,
                aspectRatio: mediaAspectRatio
            )
            ZStack {
                Color(.previewBackground)
                    .opacity(isVisible ? 1 : 0)
                    .ignoresSafeArea()

                ZStack {
                    mediaView
                        .frame(width: mediaSize.width, height: mediaSize.height)

                    if canShowMarkupOverlay, hasMarkup, showMarkupOverlay, !isMarkupMode {
                        MarkupOverlayView(drawing: markupDrawing, canvasSize: markupCanvasSize)
                            .frame(width: mediaSize.width, height: mediaSize.height)
                    }

                    if canEditMarkup {
                        PencilCanvasView(drawing: $markupDrawing, showsToolPicker: isToolPickerVisible)
                            .frame(width: mediaSize.width, height: mediaSize.height)
                            .opacity(isMarkupMode ? 1 : 0)
                            .allowsHitTesting(isMarkupMode)
                    }

                    if let scoutMetadata {
                        let hasFrameLines = !scoutMetadata.frameLines.isEmpty
                        let frameLineAspect = scoutMetadata.frameLines.first?.option.aspectRatio
                        if hasFrameLines, showFrameShading {
                            FrameShadingOverlay(configurations: scoutMetadata.frameLines)
                                .frame(width: mediaSize.width, height: mediaSize.height)
                        }
                        if hasFrameLines, showFrameLines {
                            FrameLineOverlayView(configurations: scoutMetadata.frameLines)
                                .frame(width: mediaSize.width, height: mediaSize.height)
                        }
                        if hasFrameLines, showGrid {
                            GridOverlay(aspectRatio: frameLineAspect)
                                .frame(width: mediaSize.width, height: mediaSize.height)
                        }
                        if hasFrameLines, showCrosshair {
                            CrosshairOverlay()
                                .frame(width: mediaSize.width, height: mediaSize.height)
                        }
                        if isMetadataOverlayVisible && !isMarkupMode {
                            fullscreenMetadataOverlay(scoutMetadata)
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
                .opacity(isVisible ? 1 : 0)
                .scaleEffect(isVisible ? 1 : 0.98)

            }
            .onAppear {
                updateMarkupCanvasSize(mediaSize)
            }
            .onChange(of: mediaSize) { _, newSize in
                updateMarkupCanvasSize(newSize)
            }
            .contentShape(Rectangle())
            .gesture(
                TapGesture().onEnded {
                    guard config.tapTogglesChrome else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isToolbarVisible.toggle()
                        if metadataItem != nil, !isMarkupMode {
                            isMetadataOverlayVisible = isToolbarVisible
                        }
                    }
                },
                including: .gesture
            )
            .onAppear {
                withAnimation(.easeInOut(duration: animationDuration)) {
                    isVisible = true
                }
            }
            .onChange(of: isPresented) { newValue in
                if newValue, config.showsTopToolbar {
                    isToolbarVisible = true
                    if metadataItem != nil, !isMarkupMode {
                        isMetadataOverlayVisible = true
                    }
                }
            }
            .onChange(of: isMarkupMode) { _, isActive in
                if isActive {
                    isToolbarVisible = true
                    isToolPickerVisible = true
                    isMetadataOverlayVisible = false
                } else {
                    isToolPickerVisible = false
                    if metadataItem != nil, config.showsTopToolbar {
                        isMetadataOverlayVisible = isToolbarVisible
                    }
                }
            }
            .onChange(of: canEditMarkup) { _, canEdit in
                if !canEdit {
                    isMarkupMode = false
                    isToolPickerVisible = false
                }
            }
        }
        .task(id: media.url) {
            await updateMediaAspectRatio()
        }
        .ignoresSafeArea()
        .interactiveDismissDisabled(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(isToolbarVisible ? .visible : .hidden, for: .navigationBar)
        .toolbar {
            if config.showsTopToolbar, shouldShowCloseButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        handleCloseTapped()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(8)
                    }
                    .accessibilityLabel("Close fullscreen")
                }
            }
            if config.showsTopToolbar, canEditMarkup {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 4) {
                        if isMarkupMode {
                            Button {
                                showsClearMarkupAlert = true
                            } label: {
                                Image(systemName: "eraser")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .padding(8)
                            }
                            .accessibilityLabel("Clear markup")
                        }

                        Button {
                            handleMarkupAction()
                        } label: {
                            Image(systemName: isMarkupMode ? "checkmark" : "pencil.and.scribble")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                                .padding(8)
                        }
                        .accessibilityLabel(isMarkupMode ? "Save markup" : "Markup")
                    }
                }
            }
        }
        .sheet(isPresented: $isMapSheetPresented) {
            if let scoutMetadata,
               let geo = scoutMetadata.geo {
                ScoutMapSheetView(
                    title: "Scout Map",
                    coordinate: geo.coordinate,
                    headingDegrees: scoutMetadata.orientation?.headingDegrees,
                    focalLengthMm: scoutMetadata.focalLengthMm,
                    sensorWidthMm: scoutMetadata.sensorWidthMm
                )
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isMarkupMode, canEditMarkup {
                Button {
                    isToolPickerVisible.toggle()
                } label: {
                    Image(systemName: isToolPickerVisible ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(12)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                        )
                }
                .padding(20)
                .accessibilityLabel(isToolPickerVisible ? "Hide pencil tools" : "Show pencil tools")
            }
        }
        .alert("Close markup without saving?", isPresented: $showsDiscardMarkupAlert) {
            Button("Close", role: .destructive) {
                dismissViewer()
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("You have markup on this board. Are you sure you want to close without saving?")
        }
        .alert("Clear all markup?", isPresented: $showsClearMarkupAlert) {
            Button("Clear", role: .destructive) {
                markupDrawing = PKDrawing()
                showMarkupOverlay = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all markup from the board.")
        }
    }

    @ViewBuilder
    private var mediaView: some View {
        switch media {
        case .imageURL(let url):
            ZStack {
                if let thumbnailURL {
                    CachedAsyncImage(url: thumbnailURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .opacity(hasLoadedFullImage ? 0 : 1)
                        case .failure:
                            Image(systemName: "photo")
                                .font(.system(size: 40, weight: .medium))
                                .foregroundStyle(.secondary)
                        default:
                            Color.clear
                        }
                    }
                }
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Color.clear
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .onAppear {
                                hasLoadedFullImage = true
                            }
                    case .failure:
                        Image(systemName: "photo")
                            .font(.system(size: 40, weight: .medium))
                            .foregroundStyle(.secondary)
                    @unknown default:
                        EmptyView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .videoURL(let url):
            FullscreenVideoView(url: url, config: config)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func dismissViewer() {
        withAnimation(.easeInOut(duration: animationDuration)) {
            isVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
            isPresented = false
        }
    }

    private var shouldShowCloseButton: Bool {
        true
    }

    private var canShowMarkupOverlay: Bool {
        markupConfiguration != nil && !media.isVideo
    }

    private var canEditMarkup: Bool {
        authService.allowEdit && canShowMarkupOverlay
    }

    private var hasMarkup: Bool {
        !markupDrawing.strokes.isEmpty
    }

    private var scoutMetadata: ScoutCameraMetadata? {
        metadataItem.map { ScoutCameraMetadataParser.parse($0.metadata) }.flatMap { $0 }
    }

    private func handleCloseTapped() {
                if isMarkupMode, hasMarkup {
                    showsDiscardMarkupAlert = true
                    return
                }
        dismissViewer()
    }

    private func handleMarkupAction() {
        if isMarkupMode {
            if let markupConfiguration {
                let (drawing, canvasSize) = normalizedDrawingForSave(markupDrawing)
                markupConfiguration.onSave(drawing, canvasSize)
            }
            isMarkupMode = false
            showMarkupOverlay = hasMarkup
            return
        }
        isMarkupMode = true
    }

    @ViewBuilder
    private func fullscreenMetadataOverlay(_ metadata: ScoutCameraMetadata) -> some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                metadataRow(title: "Camera", value: metadata.cameraName)
                metadataRow(title: "Camera Mode", value: metadata.cameraMode)
                metadataRow(title: "Lens", value: metadata.lensName)
                metadataRow(title: "Focal Length", value: metadata.focalLength)
                if metadata.geo != nil {
                    mapToggleButton
                }
                if !metadata.frameLines.isEmpty {
                    overlayToggles
                }
                if canShowMarkupOverlay, hasMarkup {
                    markupToggle
                }
            }
            .padding(12)
            .frame(maxWidth: isCompactPortrait ? .infinity : 420, alignment: .leading)
            //.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            //.padding([.horizontal, .bottom], 16)
            .glassEffect(
                .regular.interactive(),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .padding(.horizontal, 10)
        .padding(.vertical, 30)
    }

    private var mapToggleButton: some View {
        Button {
            isMapSheetPresented = true
        } label: {
            Text("Map")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.martiniDefault)
        .font(.system(size: 12, weight: .semibold))
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var overlayToggles: some View {
        HStack(spacing: 4) {
            overlayToggle(title: "Frames", isOn: $showFrameLines)
            overlayToggle(title: "Cross Hair", isOn: $showCrosshair)
            overlayToggle(title: "Grid", isOn: $showGrid)
            overlayToggle(title: "Shading", isOn: $showFrameShading)
        }
        .padding(.vertical, 10)
    }

    private var markupToggle: some View {
        HStack {
            overlayToggle(title: "Markup", isOn: $showMarkupOverlay)
        }
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    private func overlayToggle(title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.button)
            .font(.system(size: 12, weight: .semibold))
            .buttonBorderShape(.capsule)
            .tint(.martiniDefault)
    }

    private func metadataRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(.primary)
        }
        .font(.system(size: 14, weight: .semibold))
    }

    private func aspectFitSize(in container: CGSize, aspectRatio: CGFloat?) -> CGSize {
        guard let aspectRatio, aspectRatio > 0, container.width > 0, container.height > 0 else {
            return container
        }

        let containerAspect = container.width / container.height
        if containerAspect > aspectRatio {
            let height = container.height
            return CGSize(width: height * aspectRatio, height: height)
        } else {
            let width = container.width
            return CGSize(width: width, height: width / aspectRatio)
        }
    }

    private func updateMediaAspectRatio() async {
        await MainActor.run {
            hasLoadedFullImage = false
        }
        let ratio: CGFloat?
        switch media {
        case .imageURL(let url):
            ratio = imageAspectRatio(from: url)
            let pixelSize = imagePixelSize(from: url)
            await MainActor.run {
                mediaPixelSize = pixelSize
            }
        case .videoURL(let url):
            ratio = await videoAspectRatio(from: url)
            await MainActor.run {
                mediaPixelSize = nil
            }
        }

        guard let ratio, ratio > 0 else { return }
        await MainActor.run {
            mediaAspectRatio = ratio
        }
    }

    private func imageAspectRatio(from url: URL) -> CGFloat? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              height > 0 else {
            return nil
        }
        return width / height
    }

    private func imagePixelSize(from url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              width > 0,
              height > 0 else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    private func updateMarkupCanvasSize(_ newSize: CGSize) {
        guard newSize.width > 0, newSize.height > 0 else { return }
        let previousSize = markupCanvasSize
        markupCanvasSize = newSize

        if !hasScaledInitialDrawing {
            guard mediaAspectRatio != nil else { return }
            let sourceSize = markupConfiguration?.initialCanvasSize ?? mediaPixelSize ?? newSize
            if !markupDrawing.strokes.isEmpty, sourceSize != newSize {
                markupDrawing = scaledDrawing(markupDrawing, from: sourceSize, to: newSize)
            }
            hasScaledInitialDrawing = true
            return
        }

        guard !markupDrawing.strokes.isEmpty else { return }
        guard previousSize.width > 0, previousSize.height > 0 else { return }
        if previousSize != newSize {
            markupDrawing = scaledDrawing(markupDrawing, from: previousSize, to: newSize)
        }
    }

    private func normalizedDrawingForSave(_ drawing: PKDrawing) -> (PKDrawing, CGSize) {
        let sourceSize = markupCanvasSize
        let preferredTargetSize = markupConfiguration?.initialCanvasSize ?? mediaPixelSize ?? sourceSize
        let targetSize = preferredTargetSize.width > 0 && preferredTargetSize.height > 0
        ? preferredTargetSize
        : sourceSize

        guard targetSize.width > 0,
              targetSize.height > 0,
              sourceSize.width > 0,
              sourceSize.height > 0 else {
            return (drawing, targetSize)
        }

        if sourceSize == targetSize {
            return (drawing, targetSize)
        }

        let normalized = scaledDrawing(drawing, from: sourceSize, to: targetSize)
        return (normalized, targetSize)
    }

    private func scaledDrawing(_ drawing: PKDrawing, from sourceSize: CGSize, to targetSize: CGSize) -> PKDrawing {
        guard sourceSize.width > 0,
              sourceSize.height > 0,
              targetSize.width > 0,
              targetSize.height > 0 else {
            return drawing
        }

        let scaleX = targetSize.width / sourceSize.width
        let scaleY = targetSize.height / sourceSize.height
        if abs(scaleX - 1) < 0.001, abs(scaleY - 1) < 0.001 {
            return drawing
        }
        return drawing.transformed(using: CGAffineTransform(scaleX: scaleX, y: scaleY))
    }

    private func videoAspectRatio(from url: URL) async -> CGFloat? {
        let asset = AVAsset(url: url)
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { return nil }
            let size = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let transformed = size.applying(transform)
            let width = abs(transformed.width)
            let height = abs(transformed.height)
            guard height > 0 else { return nil }
            return width / height
        } catch {
            return nil
        }
    }
}

private struct FullscreenVideoView: View {
    let url: URL
    let config: MediaViewerConfig

    @StateObject private var playerController: MediaPlayerController

    init(url: URL, config: MediaViewerConfig) {
        self.url = url
        self.config = config
        _playerController = StateObject(wrappedValue: MediaPlayerController(url: url, config: config))
    }

    var body: some View {
        ZStack {
            if config.showsVideoControls {
                PlayerViewControllerRepresentable(
                    player: playerController.player,
                    showsPlaybackControls: true,
                    allowPiP: config.allowPiP
                )
            } else {
                PlayerLayerView(player: playerController.player)
            }

            if !config.showsVideoControls, config.showsPlayButtonOverlay {
                Button {
                    playerController.togglePlayback()
                } label: {
                    Image(systemName: playerController.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.primary)
                        .padding(18)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                        )
                }
                .accessibilityLabel(playerController.isPlaying ? "Pause" : "Play")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            playerController.handleAppear()
        }
        .onDisappear {
            playerController.handleDisappear()
        }
    }
}

final class MediaPlayerController: ObservableObject {
    @Published private(set) var isPlaying: Bool = false

    let player: AVPlayer

    private let config: MediaViewerConfig
    private var looper: AVPlayerLooper?
    private var timeControlObserver: NSKeyValueObservation?

    init(url: URL, config: MediaViewerConfig) {
        self.config = config

        if config.loop {
            let item = AVPlayerItem(url: url)
            let queuePlayer = AVQueuePlayer(items: [item])
            self.player = queuePlayer
            self.looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        } else {
            self.player = AVPlayer(url: url)
        }

        let shouldMute = !config.audioEnabled || config.startMuted
        player.isMuted = shouldMute
        player.volume = config.audioEnabled ? 1 : 0
        player.actionAtItemEnd = .pause

        timeControlObserver = player.observe(\AVPlayer.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                self?.isPlaying = player.timeControlStatus == .playing
            }
        }
    }

    func handleAppear() {
        configureAudioSession()
        if config.autoplay {
            player.play()
        }
    }

    func togglePlayback() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
    }

    func handleDisappear() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        deactivateAudioSessionIfNeeded()
    }

    deinit {
        timeControlObserver?.invalidate()
    }

    private func configureAudioSession() {
        guard config.audioEnabled else {
            player.isMuted = true
            return
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            print("Failed to activate audio session: \(error)")
        }
    }

    private func deactivateAudioSessionIfNeeded() {
        guard config.audioEnabled else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
    }
}

struct PlayerViewControllerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer
    let showsPlaybackControls: Bool
    let allowPiP: Bool

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = showsPlaybackControls
        controller.canStartPictureInPictureAutomaticallyFromInline = allowPiP
        controller.allowsPictureInPicturePlayback = allowPiP
        controller.videoGravity = .resizeAspect
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
        uiViewController.showsPlaybackControls = showsPlaybackControls
        uiViewController.canStartPictureInPictureAutomaticallyFromInline = allowPiP
        uiViewController.allowsPictureInPicturePlayback = allowPiP
    }
}

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerContainerView {
        PlayerLayerContainerView(player: player)
    }

    func updateUIView(_ uiView: PlayerLayerContainerView, context: Context) {
        uiView.updatePlayer(player)
    }
}

final class PlayerLayerContainerView: UIView {
    private let playerLayer = AVPlayerLayer()

    init(player: AVPlayer) {
        super.init(frame: .zero)
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        layer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updatePlayer(_ player: AVPlayer) {
        playerLayer.player = player
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}
