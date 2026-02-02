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
    var creativeTitleLineLimit: Int = 1
    var creativeTitleMaxWidthRatio: CGFloat = 0.7
    var frameNumberOverride: String? = nil
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

            if showFrameNumberOverlay, resolvedFrameNumber != nil {
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
            let numberBadgeTopPadding = max(2, minDimension * 0.08 * 0.25)
            let fontSize = badgeHeight * 0.42
            let horizontalPadding = badgeHeight * 0.35
            let verticalPadding = badgeHeight * 0.25

            VStack {
                HStack {
                    Spacer()
                    Text(title)
                        .font(.system(size: fontSize, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(creativeTitleLineLimit)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: geo.size.width * creativeTitleMaxWidthRatio)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.vertical, verticalPadding)
                        .background(
                            Capsule().fill(Color.martiniCreativeColor(from: frame.creativeColor))
                        )
                        .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                    Spacer()
                }
                .padding(.top, numberBadgeTopPadding)
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
                .lineLimit(2)
                .truncationMode(.tail)
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
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var resolvedMediaCrop: String? {
        guard let asset = resolvedAsset else { return nil }
        switch asset.kind {
        case .board:
            if asset.id == "photoboard" {
                return frame.photoboardCrop ?? frame.crop
            }
            return frame.boards?.first(where: { $0.id == asset.id })?.fileCrop ?? frame.crop
        case .preview:
            return frame.previewCrop ?? frame.crop
        }
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

    private static func normalizedCrop(_ crop: String?) -> String? {
        guard let crop else { return nil }
        let trimmed = crop.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var resolvedFrameNumber: String? {
        if let override = frameNumberOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return override
        }
        return frame.displayOrder
    }

    private var frameNumberLabel: String? {
        guard let displayOrder = resolvedFrameNumber else { return nil }
        return "Frame #\(displayOrder)"
    }

    private var frameNumberText: String {
        resolvedFrameNumber ?? "--"
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
            crop: resolvedMediaCrop,
            aspectRatio: aspectRatio,
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
        let crop: String?
        let aspectRatio: CGFloat
        let isSource: Bool
        let useMatchedGeometry: Bool

        var body: some View {
            Group {
                if let url {
                    if isVideo {
                        LoopingVideoView(url: url, videoGravity: imageShouldFill ? .resizeAspectFill : .resizeAspect)
                    } else {
                        if let crop = FrameLayout.normalizedCrop(crop) {
                            CroppedAsyncImage(
                                url: url,
                                crop: crop,
                                aspectRatio: aspectRatio,
                                imageShouldFill: imageShouldFill,
                                cornerRadius: cornerRadius,
                                placeholder: placeholder
                            )
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

    private struct CroppedAsyncImage: View {
        let url: URL
        let crop: String
        let aspectRatio: CGFloat
        let imageShouldFill: Bool
        let cornerRadius: CGFloat
        let placeholder: AnyView

        @State private var displayImage: UIImage?
        @State private var didFail: Bool = false

        var body: some View {
            Group {
                if let displayImage {
                    let baseImage = Image(uiImage: displayImage).resizable()
                    if imageShouldFill {
                        baseImage
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .clipped()
                    } else {
                        baseImage
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                } else if didFail {
                    placeholder
                } else {
                    ShimmerLoadingPlaceholder(
                        cornerRadius: cornerRadius,
                        overlay: placeholder
                    )
                }
            }
            .task(id: taskIdentifier) {
                await loadImage()
            }
        }

        private var taskIdentifier: String {
            "\(url.absoluteString)-\(crop)"
        }

        private func loadImage() async {
            guard let image = await CroppedImageLoader.loadImage(
                url: url,
                crop: crop,
                aspectRatio: aspectRatio
            ) else {
                await MainActor.run {
                    displayImage = nil
                    didFail = true
                }
                return
            }
            await MainActor.run {
                displayImage = image
                didFail = false
            }
        }
    }

    private enum CroppedImageLoader {
        static func loadImage(url: URL, crop: String, aspectRatio: CGFloat) async -> UIImage? {
            guard let image = await ImageCache.shared.image(for: url) else { return nil }
            let transformedCrop = parseTransformCrop(
                crop,
                imageSize: image.size,
                frameAspectRatio: aspectRatio
            )
            if let transformedCrop {
                return cropImage(image, using: transformedCrop) ?? image
            }
            return cropImage(image, using: parseCrop(crop)) ?? image
        }

        private static func cropImage(_ image: UIImage, using crop: ReferenceImageCrop?) -> UIImage? {
            guard let crop, let cgImage = image.cgImage else { return nil }
            let imageWidth = CGFloat(cgImage.width)
            let imageHeight = CGFloat(cgImage.height)

            var rect = crop.rect(in: CGSize(width: imageWidth, height: imageHeight))
            rect = rect.intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
            guard rect.width > 1, rect.height > 1 else { return nil }

            guard let cropped = cgImage.cropping(to: rect.integral) else { return nil }
            return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
        }

        private static func parseCrop(_ value: String?) -> ReferenceImageCrop? {
            guard let value, !value.isEmpty else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            if let data = trimmed.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) {
                if let dict = json as? [String: Any] {
                    let x = number(from: dict["x"])
                        ?? number(from: dict["left"])
                        ?? number(from: dict["x1"])
                    let y = number(from: dict["y"])
                        ?? number(from: dict["top"])
                        ?? number(from: dict["y1"])
                    let right = number(from: dict["right"]) ?? number(from: dict["x2"])
                    let bottom = number(from: dict["bottom"]) ?? number(from: dict["y2"])
                    var width = number(from: dict["width"]) ?? number(from: dict["w"])
                    var height = number(from: dict["height"]) ?? number(from: dict["h"])
                    if width == nil, let right, let x {
                        width = right - x
                    }
                    if height == nil, let bottom, let y {
                        height = bottom - y
                    }
                    if let x, let y, let width, let height {
                        return ReferenceImageCrop(x: x, y: y, width: width, height: height)
                    }
                } else if let array = json as? [Any], array.count >= 4 {
                    let values = array.compactMap { number(from: $0) }
                    if values.count >= 4 {
                        return ReferenceImageCrop(x: values[0], y: values[1], width: values[2], height: values[3])
                    }
                }
            }

            let separators = CharacterSet(charactersIn: ",|:")
            let parts = trimmed.components(separatedBy: separators).compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            if parts.count >= 4 {
                return ReferenceImageCrop(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
            }

            return nil
        }

        private static func parseTransformCrop(
            _ value: String?,
            imageSize: CGSize,
            frameAspectRatio: CGFloat
        ) -> ReferenceImageCrop? {
            guard let value, !value.isEmpty else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            let pattern = #"translate\(([^,]+),\s*([^)]+)\)\s*scale\(([^)]+)\)"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            guard let match = regex.firstMatch(in: trimmed, range: range),
                  match.numberOfRanges == 4,
                  let translateXRange = Range(match.range(at: 1), in: trimmed),
                  let translateYRange = Range(match.range(at: 2), in: trimmed),
                  let scaleRange = Range(match.range(at: 3), in: trimmed) else {
                return nil
            }

            let translateXText = String(trimmed[translateXRange])
            let translateYText = String(trimmed[translateYRange])
            let scaleText = String(trimmed[scaleRange])

            guard let translateXPercent = parsePercent(translateXText),
                  let translateYPercent = parsePercent(translateYText),
                  let scaleValue = Double(scaleText.trimmingCharacters(in: .whitespacesAndNewlines)),
                  scaleValue > 0,
                  frameAspectRatio > 0 else {
                return nil
            }

            let imageWidth = max(imageSize.width, 1)
            let imageHeight = max(imageSize.height, 1)
            let frameWidth = frameAspectRatio
            let frameHeight: CGFloat = 1

            let fillScale = max(frameWidth / imageWidth, frameHeight / imageHeight)
            let totalScale = fillScale * CGFloat(scaleValue)

            let scaledImageWidth = imageWidth * totalScale
            let scaledImageHeight = imageHeight * totalScale

            let translateX = CGFloat(translateXPercent) * frameWidth
            let translateY = CGFloat(translateYPercent) * frameHeight

            let frameLeft = -frameWidth / 2
            let frameTop = -frameHeight / 2
            let imageLeft = translateX - scaledImageWidth / 2
            let imageTop = translateY - scaledImageHeight / 2

            let cropXScaled = frameLeft - imageLeft
            let cropYScaled = frameTop - imageTop
            let cropWidthScaled = frameWidth
            let cropHeightScaled = frameHeight

            let cropX = cropXScaled / totalScale
            let cropY = cropYScaled / totalScale
            let cropWidth = cropWidthScaled / totalScale
            let cropHeight = cropHeightScaled / totalScale

            return ReferenceImageCrop(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
        }

        private static func parsePercent(_ value: String) -> Double? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasSuffix("%") {
                let percentValue = trimmed.dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
                guard let value = Double(percentValue) else { return nil }
                return value / 100
            }
            guard let value = Double(trimmed) else { return nil }
            return value / 100
        }

        private static func number(from value: Any?) -> CGFloat? {
            switch value {
            case let number as NSNumber:
                return CGFloat(truncating: number)
            case let string as String:
                guard let value = Double(string.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    return nil
                }
                return CGFloat(value)
            default:
                return nil
            }
        }
    }

    private struct ReferenceImageCrop {
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat

        func rect(in size: CGSize) -> CGRect {
            let imageWidth = max(size.width, 1)
            let imageHeight = max(size.height, 1)

            var cropX = x
            var cropY = y
            var cropWidth = width
            var cropHeight = height

            if cropWidth <= 1, cropHeight <= 1 {
                cropX *= imageWidth
                cropY *= imageHeight
                cropWidth *= imageWidth
                cropHeight *= imageHeight
            } else if cropWidth <= 100, cropHeight <= 100 {
                cropX = cropX / 100 * imageWidth
                cropY = cropY / 100 * imageHeight
                cropWidth = cropWidth / 100 * imageWidth
                cropHeight = cropHeight / 100 * imageHeight
            }

            cropWidth = max(1, min(cropWidth, imageWidth))
            cropHeight = max(1, min(cropHeight, imageHeight))
            cropX = max(0, min(cropX, imageWidth - cropWidth))
            cropY = max(0, min(cropY, imageHeight - cropHeight))

            return CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
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
