import SwiftUI
import UIKit
import AVFoundation
import AVKit
import CryptoKit
import PencilKit

final class VideoCacheManager {
    static let shared = VideoCacheManager()

    private let fileManager = FileManager.default
    private let ioQueue = DispatchQueue(label: "VideoCacheManager.io")
    private let cacheDirectory: URL
    private var inFlightDownloads: [URL: [(URL?) -> Void]] = [:]
    private let unsupportedCacheExtensions: Set<String> = ["m3u8"]

    private init() {
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        cacheDirectory = cachesDirectory?.appendingPathComponent("VideoCache", isDirectory: true) ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    func existingCachedFile(for url: URL) -> URL? {
        guard shouldCache(url: url) else { return nil }
        let destination = cachedFileURL(for: url)
        return fileManager.fileExists(atPath: destination.path) ? destination : nil
    }

    func fetchCachedURL(for url: URL, completion: @escaping (URL?) -> Void) {
        guard shouldCache(url: url) else {
            completion(nil)
            return
        }

        if let cached = existingCachedFile(for: url) {
            completion(cached)
            return
        }

        ioQueue.async { [weak self] in
            guard let self else { return }

            if let cached = self.existingCachedFile(for: url) {
                DispatchQueue.main.async {
                    completion(cached)
                }
                return
            }

            self.inFlightDownloads[url, default: []].append(completion)
            if self.inFlightDownloads[url]?.count ?? 0 > 1 {
                return
            }

            let task = URLSession.shared.downloadTask(with: url) { tempURL, _, _ in
                var finalURL: URL?

                if let tempURL {
                    do {
                        try self.fileManager.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
                        let destination = self.cachedFileURL(for: url)
                        if self.fileManager.fileExists(atPath: destination.path) {
                            try self.fileManager.removeItem(at: destination)
                        }
                        try self.fileManager.moveItem(at: tempURL, to: destination)
                        finalURL = destination
                    } catch {
                        finalURL = nil
                    }
                }

                self.ioQueue.async {
                    let completions = self.inFlightDownloads.removeValue(forKey: url) ?? []
                    DispatchQueue.main.async {
                        completions.forEach { completion in
                            completion(finalURL)
                        }
                    }
                }
            }

            task.resume()
        }
    }

    private func cachedFileURL(for url: URL) -> URL {
        cacheDirectory.appendingPathComponent(filename(for: url))
    }

    private func filename(for url: URL) -> String {
        let data = Data(url.absoluteString.utf8)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let fileExtension = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
        return "\(hash).\(fileExtension)"
    }

    private func shouldCache(url: URL) -> Bool {
        !unsupportedCacheExtensions.contains(url.pathExtension.lowercased())
    }
}

struct FrameLayout: View {
    let frame: Frame
    var primaryAsset: FrameAssetItem? = nil
    var title: String?
    var subtitle: String?
    var showStatusBadge: Bool = true
    var showFrameNumberOverlay: Bool = true
    var showFrameTimeOverlay: Bool = true
    var showPinnedBoardOverlay: Bool = false
    var showMetadataOverlay: Bool = false
    var metadataTapAction: (() -> Void)? = nil
    var showTextBlock: Bool = true
    var showCreativeTitleOverlay: Bool = false
    var cornerRadius: CGFloat = 8
    var enablesFullScreen: Bool = true
    var doneCrossLineWidthOverride: Double? = nil
    var usePinnedBoardMarkupFallback: Bool = false


    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.fullscreenMediaCoordinator) private var fullscreenCoordinator
    @AppStorage("showDoneCrosses") private var showDoneCrosses: Bool = true
    @AppStorage("doneCrossLineWidth") private var doneCrossLineWidth: Double = UIControlConfig.crossMarkThicknessDefault
    @AppStorage("markerBorderWidth") private var markerBorderWidth: Double = UIControlConfig.borderThicknessDefault
    @Namespace private var fullscreenNamespace
    @State private var borderScale: CGFloat = 1.0
    @State private var omitOverlayOpacity: Double = 0
    @State private var doneFirstLineProgress: CGFloat = 0
    @State private var doneSecondLineProgress: CGFloat = 0
    @State private var lastAnimatedStatus: FrameStatus = .none

    private struct BoardAnnotationData {
        let drawing: PKDrawing
        let canvasSize: CGSize?
    }

    private var resolvedTitle: String? {
        if let title, !title.isEmpty {
            return title
        }
        if let caption = frame.caption, !caption.isEmpty {
            return caption
        }

        return nil
    }

    private var resolvedSubtitle: String? {
        if let subtitle, !subtitle.isEmpty {
            return subtitle
        }

        return nil
    }

    private var resolvedCreativeTitle: String? {
        let trimmed = frame.creativeTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        let layout: AnyLayout = (hSizeClass == .regular)
        ? AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))

        layout {
            imageCard
            if showTextBlock {
                textBlock
            }
        }
    }

    @ViewBuilder
    private var imageCard: some View {
        let card = ZStack {
            let hasAnnotation = boardAnnotationData?.drawing.strokes.isEmpty == false
            let shouldFillImage = !hasAnnotation
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.gray.opacity(0.2))
                .overlay(alignment: .center) {
                    heroMedia(isFullscreen: false, shouldFillImage: shouldFillImage)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

            if let annotation = boardAnnotationData, !annotation.drawing.strokes.isEmpty {
                MarkupOverlayView(
                    drawing: annotation.drawing,
                    contentMode: .fit,
                    canvasSize: annotation.canvasSize
                )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }

            GeometryReader { geo in
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(borderColor, lineWidth: borderWidth(for: geo.size))
                    .allowsHitTesting(false)
            }

            if let resolvedTitle {
                captionOverlay(for: resolvedTitle)
            }

            if showStatusBadge {
                statusOverlay(for: frame.statusEnum)
            }

            if showCreativeTitleOverlay, let creativeTitle = resolvedCreativeTitle {
                creativeTitleOverlay(creativeTitle)
            }

            if showFrameNumberOverlay {
                GeometryReader { geo in
                    let diameter = max(18, geo.size.width * 0.08) // 8% of width with a minimum

                    VStack {
                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.8))
                                    .frame(width: diameter, height: diameter)
                                Text(frameNumberText)
                                    .font(.system(size: diameter * 0.53, weight: .semibold))
                                    .foregroundColor(.white)
                                    .minimumScaleFactor(0.5)
                            }
                        }
                        .padding(max(2, diameter * 0.25))
                        Spacer()
                    }
                }
            }

            if showMetadataOverlay {
                GeometryReader { geo in
                    let diameter = max(18, geo.size.width * 0.08)

                    VStack {
                        HStack {
                            Button {
                                metadataTapAction?()
                            } label: {
                                Circle()
                                    .fill(Color.black.opacity(0.8))
                                    .frame(width: diameter, height: diameter)
                                    .overlay(
                                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                                            .font(.system(size: diameter * 0.42, weight: .semibold))
                                            .foregroundColor(.white)
                                    )
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                        .padding(max(2, diameter * 0.25))
                        Spacer()
                    }
                }
            }

            if showPinnedBoardOverlay, frameHasPinnedBoard {
                GeometryReader { geo in
                    let diameter = max(18, geo.size.width * 0.08)

                    VStack {
                        HStack {
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.8))
                                    .frame(width: diameter, height: diameter)
                                Image(systemName: "pin.fill")
                                    .font(.system(size: diameter * 0.52, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            Spacer()
                        }
                        .padding(max(2, diameter * 0.25))
                        Spacer()
                    }
                }
            }

            if showFrameTimeOverlay {
                if frameTimeOverlay {
                    GeometryReader { geo in
                        let minDimension = min(geo.size.width, geo.size.height)
                        let badgeHeight = max(18, minDimension * 0.12)
                        let maxBadgeWidth = geo.size.width * 0.65

                        VStack {
                            Spacer()
                            HStack {
                                timeBadge(height: badgeHeight, maxWidth: maxBadgeWidth)
                                Spacer()
                            }
                            .padding(max(2, badgeHeight * 0.25))
                        }
                    }
                }
            }
        }
        let animatedCard = card
            .aspectRatio(aspectRatio, contentMode: .fit)
            .contentShape(Rectangle())
            .scaleEffect(borderScale)
            .animation(.spring(response: 0.3, dampingFraction: 0.55, blendDuration: 0.12), value: borderScale)
//            .shadow(color: borderColor.opacity(0.8), radius: 8, x: 0, y: 0)
//            .shadow(color: borderColor.opacity(0.5), radius: 40, x: 0, y: 0)
//            .shadow(color: borderColor.opacity(0.3), radius: 80, x: 0, y: 0)
//            .overlay {
//                RoundedRectangle(cornerRadius: 12)
//                    .stroke(borderColor.opacity(0.5), lineWidth: 10)
//                    .blur(radius: 10)
//            }
            .onAppear {
                configureInitialStatusAnimation()
            }
            .onChange(of: frame.statusEnum) { newStatus in
                guard newStatus != lastAnimatedStatus else { return }
                lastAnimatedStatus = newStatus
                animateStatusChange(to: newStatus)
            }
            .onChange(of: frame.id) { _ in
                configureInitialStatusAnimation()
            }

        if enablesFullScreen, resolvedMediaURL != nil {
            animatedCard
                .onTapGesture {
                    guard let resolvedMediaURL else { return }
                    let media: MediaItem = shouldPlayAsVideo
                        ? .videoURL(resolvedMediaURL)
                        : .imageURL(resolvedMediaURL)
                    fullscreenCoordinator?.configuration = FullscreenMediaConfiguration(
                        media: media,
                        config: .default,
                        metadataItem: nil,
                        thumbnailURL: resolvedThumbnailURL,
                        markupConfiguration: nil,
                        startsInMarkupMode: false
                    )
                }
        } else {
            animatedCard
        }
    }

    private func creativeTitleOverlay(_ title: String) -> some View {
        GeometryReader { geo in
            let minDimension = min(geo.size.width, geo.size.height)
            let badgeHeight = max(18, minDimension * 0.12)
            let fontSize = badgeHeight * 0.42
            let horizontalPadding = badgeHeight * 0.35
            let verticalPadding = badgeHeight * 0.25

            VStack {
                HStack {
                    Spacer()
                    Text(title)
                        .font(.system(size: fontSize, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.vertical, verticalPadding)
                        .background(
                            Capsule().fill(Color.martiniCreativeColor(from: frame.creativeColor))
                        )
                        .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                    Spacer()
                }
                .padding(.top, 8)
                Spacer()
            }
        }
    }

    private func captionOverlay(for text: String) -> some View {
        return GeometryReader { geo in
            let referenceWidth = geo.size.width
            //let fontSize = max(14, min(referenceWidth * 0.06, 28))
            let fontSize = referenceWidth * 0.06
            let horizontalPadding = referenceWidth * 0.08
            let verticalPadding = referenceWidth * 0.05

            Text(text)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .frame(width: geo.size.width, height: geo.size.height)
                .background(Color.black.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .minimumScaleFactor(0.5)
                .allowsHitTesting(false)
        }
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let resolvedTitle {
                if let attributedTitle = attributedStringFromHTML(resolvedTitle) {
                    Text(attributedTitle)
                        .font(.system(size: 14, weight: .semibold))
                } else {
                    Text(resolvedTitle)
                        .font(.system(size: 14, weight: .semibold))
                }
            }

            if let resolvedSubtitle {
                let subtitleSize = dynamicSubtitleFontSize(for: 200)
                if let attributedSubtitle = attributedStringFromHTML(resolvedSubtitle, defaultColor: defaultDescriptionUIColor) {
                    Text(attributedSubtitle)
                        .font(.system(size: subtitleSize, weight: .semibold))
                        .foregroundColor(descriptionColor)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Text(resolvedSubtitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(descriptionColor)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        //.lineLimit(2)
                }
            }
        }
    }

    private func scaledBorderWidth(for size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else {
            return CGFloat(markerBorderWidth)
        }
        let minDimension = min(size.width, size.height)
        let percentage = max(markerBorderWidth, 0) * 0.01
        return minDimension * percentage
    }

    private func borderWidth(for size: CGSize) -> CGFloat {
        frame.statusEnum == .none ? 1 : scaledBorderWidth(for: size)
    }

    private var borderColor: Color {
        let status = frame.statusEnum

        switch status {
        case .done:
            return .red
        case .here:
            return .green
        case .next:
            return .orange
        case .omit:
            return .red
        case .none:
            return .white.opacity(0.3)
        }
    }

    private var statusText: String? {
        let text = frame.status?.uppercased() ?? ""
        return text.isEmpty ? nil : text
    }

    private var resolvedAsset: FrameAssetItem? {
        primaryAsset ?? frame.availableAssets.first
    }

    private var boardMetadata: JSONValue? {
        guard let resolvedAsset, resolvedAsset.kind == .board else { return nil }
        return metadataForBoard(id: resolvedAsset.id)
    }

    private var pinnedBoardMetadata: JSONValue? {
        guard let pinnedBoard = frame.boards?.first(where: { $0.isPinned }) else { return nil }
        return metadataForBoard(id: pinnedBoard.id)
    }

    private func metadataForBoard(id: String) -> JSONValue? {
        guard let board = frame.boards?.first(where: { $0.id == id }) else { return nil }
        if case .null = board.metadata {
            return nil
        }
        return board.metadata
    }

    private var boardAnnotationData: BoardAnnotationData? {
        if let resolvedMetadata = boardMetadata {
            return annotationData(from: resolvedMetadata)
        }
        if usePinnedBoardMarkupFallback, let pinnedMetadata = pinnedBoardMetadata {
            return annotationData(from: pinnedMetadata)
        }
        return nil
    }

    private var resolvedMediaURL: URL? {
        if let primaryURL = resolvedAsset?.url {
            return primaryURL
        }

        let urlCandidates = [
            frame.board,
            frame.boardThumb,
            frame.photoboard,
            frame.photoboardThumb,
            frame.preview,
            frame.previewThumb,
            frame.captureClip,
            frame.captureClipThumbnail
        ]
        for candidate in urlCandidates {
            if let candidate, let url = URL(string: candidate) {
                return url
            }
        }

        return nil
    }

    private var resolvedThumbnailURL: URL? {
        if let thumbnailURL = resolvedAsset?.thumbnailURL {
            return thumbnailURL
        }

        let urlCandidates = [
            frame.boardThumb,
            frame.photoboardThumb,
            frame.previewThumb,
            frame.captureClipThumbnail
        ]
        for candidate in urlCandidates {
            if let candidate, let url = URL(string: candidate) {
                return url
            }
        }

        return nil
    }

    private var shouldPlayAsVideo: Bool {
        guard let url = resolvedMediaURL else { return false }

        if let asset = resolvedAsset, asset.isVideo {
            return true
        }

        let lowercasedExtension = url.pathExtension.lowercased()
        let knownVideoExtensions: Set<String> = ["mp4", "mov", "m4v", "webm", "mkv"]
        if knownVideoExtensions.contains(lowercasedExtension) { return true }

        // Allow common streaming URL hints (e.g. HLS)
        return url.absoluteString.lowercased().contains(".m3u8")
    }

    private var frameNumberLabel: String? {
        guard let displayOrder = frame.displayOrder else { return nil }
        return "Frame #\(displayOrder)"
    }

    private var frameNumberText: String {
        frame.displayOrder ?? "--"
    }

    private var frameStartTimeText: String? { frame.formattedStartTime }

    private var frameTimeOverlay: Bool { frameStartTimeText != nil }

    private var frameHasPinnedBoard: Bool {
        frame.boards?.contains(where: { $0.isPinned }) ?? false
    }

    private func annotationData(from metadata: JSONValue?) -> BoardAnnotationData? {
        guard let metadata, case .object(let root) = metadata,
              let annotationValue = root["annotation"],
              case .object(let annotation) = annotationValue,
              let dataValue = annotation["data_base64"],
              case .string(let base64) = dataValue,
              let data = Data(base64Encoded: base64)
        else {
            return nil
        }
        guard let drawing = try? PKDrawing(data: data) else { return nil }
        let canvasSize = annotationCanvasSize(from: annotation)
        return BoardAnnotationData(drawing: drawing, canvasSize: canvasSize)
    }

    private func annotationCanvasSize(from annotation: [String: JSONValue]) -> CGSize? {
        guard let widthValue = annotation["canvas_width"],
              let heightValue = annotation["canvas_height"],
              case .number(let width) = widthValue,
              case .number(let height) = heightValue,
              width > 0,
              height > 0 else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    @ViewBuilder
    private func timeBadge(height: CGFloat, maxWidth: CGFloat) -> some View {
        if let frameStartTimeText {
            let fontSize = height * 0.42
            let contentSpacing = height * 0.28
            let horizontalPadding = height * 0.35
            let verticalPadding = height * 0.25

            HStack(spacing: contentSpacing) {
                Image(systemName: "video.fill")
                Text(frameStartTimeText)
            }
            .font(.system(size: fontSize, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .fixedSize(horizontal: true, vertical: false)
            .background(Color.black.opacity(0.8))
            .foregroundColor(.white)
            .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private func statusOverlay(for status: FrameStatus) -> some View {
        switch status {
        case .done:
            if showDoneCrosses {
                // Red X lines from corner to corner
                GeometryReader { geometry in
                    let lineWidth = scaledCrossLineWidth(for: geometry.size)
                    ZStack {
                        Path { path in
                            path.move(to: .zero)
                            path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                        }
                        .trim(from: 0, to: doneFirstLineProgress)
                        .stroke(Color.red, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

                        Path { path in
                            path.move(to: CGPoint(x: geometry.size.width, y: 0))
                            path.addLine(to: CGPoint(x: 0, y: geometry.size.height))
                        }
                        .trim(from: 0, to: doneSecondLineProgress)
                        .stroke(Color.red, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    }
                }
                .aspectRatio(aspectRatio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }

        case .omit:
            // Transparent overlay layer
            Color.red.opacity(omitOverlayOpacity)
                .cornerRadius(cornerRadius)
                .overlay {
                    GeometryReader { geometry in
                        let fontSize = min(geometry.size.width, geometry.size.height) * 0.4
                        Text("OMIT")
                            .font(.system(size: fontSize, weight: .bold))
                            .foregroundColor(.red)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }

        case .here, .next, .none:
            EmptyView()
        }
    }

    private func configureInitialStatusAnimation() {
        lastAnimatedStatus = frame.statusEnum
        omitOverlayOpacity = frame.statusEnum == .omit ? 0.5 : 0
        let isDone = frame.statusEnum == .done
        doneFirstLineProgress = isDone ? 1 : 0
        doneSecondLineProgress = isDone ? 1 : 0
        borderScale = 1
    }

    private func scaledCrossLineWidth(for size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else {
            return CGFloat(doneCrossLineWidthOverride ?? doneCrossLineWidth)
        }
        let minDimension = min(size.width, size.height)
        let percentage = max(doneCrossLineWidthOverride ?? doneCrossLineWidth, 0) * 0.01
        return minDimension * percentage
    }

    private func animateStatusChange(to status: FrameStatus) {
        animateBorderBounce()

        switch status {
        case .omit:
            withAnimation(.easeOut(duration: 0.1)) {
                doneFirstLineProgress = 0
                doneSecondLineProgress = 0
            }
            withAnimation(.easeInOut(duration: 0.35)) {
                omitOverlayOpacity = 0.5
            }
        case .done:
            withAnimation(.easeOut(duration: 0.2)) {
                omitOverlayOpacity = 0
            }
            doneFirstLineProgress = 0
            doneSecondLineProgress = 0
            withAnimation(.timingCurve(0.15, 0.0, 0.85, 1.0, duration: 0.25)) {
                doneFirstLineProgress = 1
            }
            withAnimation(.timingCurve(0.15, 0.0, 0.85, 1.0, duration: 0.25).delay(0.25)) {
                doneSecondLineProgress = 1
            }
        case .here, .next, .none:
            withAnimation(.easeOut(duration: 0.25)) {
                omitOverlayOpacity = 0
                doneFirstLineProgress = 0
                doneSecondLineProgress = 0
            }
        }
    }

    private func animateBorderBounce() {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.55, blendDuration: 0.08)) {
            borderScale = 1.06
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0.08).delay(0.08)) {
            borderScale = 1.0
        }
    }

    private var placeholder: some View {
        VStack {
//            Image(systemName: "photo")
//                .font(.system(size: 40))
//                .foregroundColor(.gray.opacity(0.5))
//            if showFrameNumberOverlay, let frameNumberLabel {
//                Text(frameNumberLabel)
//                    .font(.caption)
//                    .foregroundColor(.gray)
//            }
        }
    }

    private var mediaHeroID: String { "frame-media-\(frame.id)" }

    @ViewBuilder
    private func heroMedia(isFullscreen: Bool, shouldFillImage: Bool) -> some View {
        HeroMediaView(
            url: resolvedMediaURL,
            isVideo: shouldPlayAsVideo,
            cornerRadius: isFullscreen ? 0 : cornerRadius,
            namespace: fullscreenNamespace,
            heroID: mediaHeroID,
            frameNumberLabel: frameNumberLabel,
            placeholder: AnyView(placeholder),
            imageShouldFill: isFullscreen ? false : shouldFillImage,
            isSource: !isFullscreen,
            useMatchedGeometry: !isFullscreen
        )
        // Prevent the image content from animating independently when the card resizes
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    struct HeroMediaView: View {
        let url: URL?
        let isVideo: Bool
        let cornerRadius: CGFloat
        let namespace: Namespace.ID
        let heroID: String
        let frameNumberLabel: String?
        let placeholder: AnyView
        let imageShouldFill: Bool
        let isSource: Bool
        let useMatchedGeometry: Bool

        var body: some View {
            Group {
                if let url {
                    if isVideo {
                        LoopingVideoView(url: url, videoGravity: imageShouldFill ? .resizeAspectFill : .resizeAspect)
                    } else {
                        CachedAsyncImage(url: url) { phase in
                            switch phase {
                            case let .success(image):
                                let baseImage = image.resizable()
                                let renderedImage: AnyView = imageShouldFill
                                    ? AnyView(
                                        baseImage
                                            .scaledToFill()
                                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                                            .clipped()
                                    )
                                    : AnyView(
                                        baseImage
                                            .scaledToFit()
                                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                                    )
                                renderedImage
                            case .empty:
                                AnyView(
                                    ShimmerLoadingPlaceholder(
                                        cornerRadius: cornerRadius,
                                        overlay: placeholder
                                    )
                                )
                            case .failure:
                                placeholder
                            @unknown default:
                                placeholder
                            }
                        }
                    }
            } else {
                placeholder
            }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .modifier(MatchedGeometryModifier(useMatchedGeometry: useMatchedGeometry, heroID: heroID, namespace: namespace, isSource: isSource))
        }
    }

    private struct MatchedGeometryModifier: ViewModifier {
        let useMatchedGeometry: Bool
        let heroID: String
        let namespace: Namespace.ID
        let isSource: Bool

        func body(content: Content) -> some View {
            if useMatchedGeometry {
                content.matchedGeometryEffect(id: heroID, in: namespace, isSource: isSource)
            } else {
                content
            }
        }
    }

    struct ShimmerLoadingPlaceholder: View {
        let cornerRadius: CGFloat
        let overlay: AnyView?

        init(cornerRadius: CGFloat, overlay: AnyView? = nil) {
            self.cornerRadius = cornerRadius
            self.overlay = overlay
        }

        var body: some View {
            ZStack {
                ShimmerView(cornerRadius: cornerRadius)
                if let overlay {
                    overlay
                }
            }
        }
    }

    struct ShimmerView: View {
        var cornerRadius: CGFloat
        var baseOpacity: Double = 0
        var highlightOpacity: Double = 0.1

        @State private var offsetProgress: CGFloat = -1.2

        private var animation: Animation {
            .linear(duration: 1.2).repeatForever(autoreverses: false)
        }

        var body: some View {
            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.width
                let gradientWidth = width * 2
                let gradientHeight = height
                let bgColor = Color.gray.opacity(0.2)
                let baseColor = Color.gray.opacity(baseOpacity)
                let highlight = Color.white.opacity(highlightOpacity)

                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(bgColor)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(
                                LinearGradient(
                                    colors: [baseColor, highlight, baseColor],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: gradientWidth, height: gradientHeight)
                            .rotationEffect(.degrees(45))
                            .offset(x: offsetProgress * width)
                    }
                    .clipped()
                    .onAppear {
                        offsetProgress = -2
                        withAnimation(animation) {
                            offsetProgress = 2
                        }
                    }
            }
        }
    }

    private var descriptionColor: Color {
        .martiniDefaultDescriptionColor
    }

    private var defaultDescriptionUIColor: UIColor {
        UIColor(named: "MartiniDefaultDescriptionColor") ?? .label
    }

    private var aspectRatio: CGFloat {
        guard let ratioString = frame.creativeAspectRatio,
              let parsedRatio = FrameLayout.aspectRatio(from: ratioString) else {
            return 16.0 / 9.0
        }

        return parsedRatio
    }

    static func aspectRatio(from ratioString: String) -> CGFloat? {
        let separators = CharacterSet(charactersIn: ":/xX").union(.whitespaces)
        let components = ratioString
            .split(whereSeparator: { separator in
                separator.unicodeScalars.contains { separators.contains($0) }
            })
            .map(String.init)

        guard components.count == 2,
              let width = Double(components[0]),
              let height = Double(components[1]),
              height != 0 else {
            return nil
        }

        return CGFloat(width / height)
    }
    
    private func dynamicSubtitleFontSize(for width: CGFloat) -> CGFloat {
        // Proportional scaling: ~5% of available width
        let proportional = width * 0.05
        // Clamp to sensible bounds
        let minSize: CGFloat = 4
        let maxSize: CGFloat = 20
        return max(minSize, min(proportional, maxSize))
    }
}

struct LoopingVideoView: UIViewRepresentable {
    let url: URL
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill

    func makeUIView(context _: Context) -> LoopingPlayerView {
        LoopingPlayerView(url: url, videoGravity: videoGravity)
    }

    func updateUIView(_ uiView: LoopingPlayerView, context _: Context) {
        uiView.update(with: url, videoGravity: videoGravity)
    }
}

final class LoopingPlayerView: UIView {
    private let playerLayer = AVPlayerLayer()
    private var playerLooper: AVPlayerLooper?
    private var queuePlayer: AVQueuePlayer?
    private var player: AVPlayer?
    private var currentURL: URL?
    private var resolvedPlaybackURL: URL?
    private var endObserver: NSObjectProtocol?
    private var didBecomeActiveObserver: NSObjectProtocol?
    private var willResignActiveObserver: NSObjectProtocol?
    private var currentVideoGravity: AVLayerVideoGravity = .resizeAspectFill

    init(url: URL, videoGravity: AVLayerVideoGravity = .resizeAspectFill) {
        super.init(frame: .zero)
        currentVideoGravity = videoGravity
        setupPlayerLayer()
        setupLifecycleObservers()
        update(with: url, videoGravity: videoGravity)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupPlayerLayer()
        setupLifecycleObservers()
    }

    deinit {
        endObserver.map(NotificationCenter.default.removeObserver)
        didBecomeActiveObserver.map(NotificationCenter.default.removeObserver)
        willResignActiveObserver.map(NotificationCenter.default.removeObserver)
        queuePlayer?.pause()
        player?.pause()
    }

    func update(with url: URL, videoGravity: AVLayerVideoGravity? = nil) {
        if let videoGravity, videoGravity != currentVideoGravity {
            currentVideoGravity = videoGravity
            playerLayer.videoGravity = videoGravity
        }
        guard url != currentURL else { return }
        currentURL = url

        print("[LoopingPlayerView] Loading video URL: \(url.absoluteString)")

        if let cached = VideoCacheManager.shared.existingCachedFile(for: url) {
            print("[LoopingPlayerView] Using cached video URL: \(cached.absoluteString)")
            configurePlayer(with: cached)
            return
        }

        print("[LoopingPlayerView] Using remote video URL: \(url.absoluteString)")
        configurePlayer(with: url)

        VideoCacheManager.shared.fetchCachedURL(for: url) { [weak self] cachedURL in
            guard let self, let cachedURL, self.currentURL == url else { return }
            print("[LoopingPlayerView] Updated to cached video URL: \(cachedURL.absoluteString)")
            if cachedURL != self.resolvedPlaybackURL {
                self.configurePlayer(with: cachedURL)
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }

    private func setupPlayerLayer() {
        playerLayer.videoGravity = currentVideoGravity
        layer.addSublayer(playerLayer)
    }

    private func setupLifecycleObservers() {
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resumePlayback()
        }

        willResignActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.pausePlayback()
        }
    }

    private func resumePlayback() {
        if let queuePlayer {
            queuePlayer.play()
            return
        }

        if let player {
            player.play()
            return
        }

        playerLayer.player?.play()
    }

    private func pausePlayback() {
        queuePlayer?.pause()
        player?.pause()
        playerLayer.player?.pause()
    }

    private func configurePlayer(with url: URL) {
        resolvedPlaybackURL = url

        endObserver.map(NotificationCenter.default.removeObserver)
        endObserver = nil

        if url.pathExtension.lowercased() == "m3u8" {
            let playerItem = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: playerItem)
            player.isMuted = true
            player.actionAtItemEnd = .none

            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: playerItem,
                queue: .main
            ) { [weak self] _ in
                player.seek(to: .zero)
                player.play()
            }

            player.play()
            playerLayer.player = player

            self.player = player
            queuePlayer = nil
            playerLooper = nil
        } else {
            let item = AVPlayerItem(url: url)
            let queuePlayer = AVQueuePlayer()
            queuePlayer.isMuted = true
            queuePlayer.actionAtItemEnd = .none

            let looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
            queuePlayer.play()

            playerLayer.player = queuePlayer

            self.queuePlayer = queuePlayer
            playerLooper = looper
            player = nil
        }
    }
}
