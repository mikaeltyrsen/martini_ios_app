import SwiftUI
import UIKit
import AVFoundation
import AVKit
import CryptoKit

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
    var showTextBlock: Bool = true
    var cornerRadius: CGFloat = 8
    var enablesFullScreen: Bool = true

    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPresentingFullScreen: Bool = false

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
        .fullScreenCover(isPresented: $isPresentingFullScreen) {
            FullscreenMediaView(
                url: resolvedMediaURL,
                isVideo: shouldPlayAsVideo,
                aspectRatio: aspectRatio,
                title: resolvedTitle,
                frameNumberLabel: frameNumberLabel
            )
        }
    }

    @ViewBuilder
    private var imageCard: some View {
        let card = ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.gray.opacity(0.2))
                .overlay(
                    Group {
                        if let url = resolvedMediaURL {
                            if shouldPlayAsVideo {
                                LoopingVideoView(url: url)
                            } else {
                                CachedAsyncImage(url: url) { phase in
                                    switch phase {
                                    case let .success(image):
                                        AnyView(
                                            image
                                                .resizable()
                                                .scaledToFill()
                                        )
                                    case .empty:
                                        AnyView(ProgressView())
                                    case .failure:
                                        AnyView(placeholder)
                                    @unknown default:
                                        AnyView(placeholder)
                                    }
                                }
                            }
                        } else {
                            placeholder
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

            if let resolvedTitle {
                captionOverlay(for: resolvedTitle)
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

            if showFrameTimeOverlay {
                if frameTimeOverlay{
                    GeometryReader { geo in
                        let height = max(18, geo.size.height * 0.08)

                        VStack {
                            Spacer()
                            HStack {
                                timeBadge(height: height)
                                Spacer()
                            }
                            .padding(max(2, height * 0.25))
                        }
                    }
                }
            }

            if showStatusBadge {
                statusOverlay(for: frame.statusEnum)
            }

        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .contentShape(Rectangle())
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        )

        if enablesFullScreen, resolvedMediaURL != nil {
            card
                .onTapGesture {
                    isPresentingFullScreen = true
                }
        } else {
            card
        }
    }

    private func captionOverlay(for text: String) -> some View {
        let captionText: Text

        if let attributedTitle = attributedString(fromHTML: text, defaultColor: UIColor.white) {
            captionText = Text(attributedTitle)
        } else {
            captionText = Text(text)
        }

        return GeometryReader { geo in
            let minDimension = min(geo.size.width, geo.size.height)
            let fontSize = max(14, min(minDimension * 0.06, 28))
            let horizontalPadding = minDimension * 0.08
            let verticalPadding = minDimension * 0.05

            captionText
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
                if let attributedTitle = attributedString(fromHTML: resolvedTitle) {
                    Text(attributedTitle)
                        .font(.system(size: 14, weight: .semibold))
                } else {
                    Text(resolvedTitle)
                        .font(.system(size: 14, weight: .semibold))
                }
            }

            if let resolvedSubtitle {
                let subtitleSize = dynamicSubtitleFontSize(for: 200)
                if let attributedSubtitle = attributedString(fromHTML: resolvedSubtitle, defaultColor: defaultDescriptionUIColor) {
                    Text(attributedSubtitle)
                        .font(.system(size: subtitleSize, weight: .semibold))
                        .foregroundColor(descriptionColor)
                } else {
                    Text(resolvedSubtitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(descriptionColor)
                        //.lineLimit(2)
                }
            }
        }
    }

    private var borderWidth: CGFloat {
        frame.statusEnum != .none ? 3 : 1
    }

    private var borderColor: Color {
        let status = frame.statusEnum

        switch status {
        case .done:
            return .red
        case .inProgress:
            return .green
        case .skip:
            return .red
        case .upNext:
            return .orange
        case .none:
            return .gray.opacity(0.3)
        }
    }

    private var statusText: String? {
        let text = frame.status?.uppercased() ?? ""
        return text.isEmpty ? nil : text
    }

    private var resolvedAsset: FrameAssetItem? {
        primaryAsset ?? frame.availableAssets.first
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
        frame.frameNumber > 0 ? "Frame #\(frame.frameNumber)" : nil
    }

    private var frameNumberText: String {
        frame.frameNumber > 0 ? "\(frame.frameNumber)" : "--"
    }

    private var frameStartTimeText: String? { frame.formattedStartTime }

    private var frameTimeOverlay: Bool { frameStartTimeText != nil }

    @ViewBuilder
    private func timeBadge(height: CGFloat) -> some View {
        if let frameStartTimeText {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                Text(frameStartTimeText)
            }
            .font(.system(size: height * 0.4, weight: .semibold))
            .padding(.horizontal, height * 0.35)
            .padding(.vertical, height * 0.25)
            .background(Color.black.opacity(0.8))
            .foregroundColor(.white)
            .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private func statusOverlay(for status: FrameStatus) -> some View {
        switch status {
        case .done:
            // Red X lines from corner to corner
            GeometryReader { geometry in
                ZStack {
                    // Diagonal line from top-left to bottom-right
                    Path { path in
                        path.move(to: .zero)
                        path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                    }
                    .stroke(Color.red, lineWidth: 5)

                    // Diagonal line from top-right to bottom-left
                    Path { path in
                        path.move(to: CGPoint(x: geometry.size.width, y: 0))
                        path.addLine(to: CGPoint(x: 0, y: geometry.size.height))
                    }
                    .stroke(Color.red, lineWidth: 5)
                }
            }
            .aspectRatio(aspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

        case .skip:
            // Red transparent layer
            Color.red.opacity(0.3)
                .cornerRadius(cornerRadius)

        case .inProgress, .upNext, .none:
            EmptyView()
        }
    }

    private var placeholder: some View {
        VStack {
            Image(systemName: "photo")
                .font(.system(size: 40))
                .foregroundColor(.gray.opacity(0.5))
            if showFrameNumberOverlay, let frameNumberLabel {
                Text(frameNumberLabel)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }

    private struct FullscreenMediaView: View {
        let url: URL?
        let isVideo: Bool
        let aspectRatio: CGFloat
        let title: String?
        let frameNumberLabel: String?

        @Environment(\.dismiss) private var dismiss

        var body: some View {
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()

                VStack(spacing: 12) {
                    Spacer()

                    mediaContent
                        .frame(maxWidth: .infinity)
                        .aspectRatio(aspectRatio, contentMode: .fit)

                    metadata

                    Spacer()
                }

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(8)
                }
                .accessibilityLabel("Close fullscreen")
                .padding(16)
            }
        }

        @ViewBuilder
        private var mediaContent: some View {
            if let url {
                if isVideo {
                    LoopingVideoView(url: url)
                        .clipped()
                } else {
                    CachedAsyncImage(url: url) { phase in
                        switch phase {
                        case let .success(image):
                            image
                                .resizable()
                                .scaledToFit()
                        case .empty:
                            ProgressView()
                        case .failure:
                            fallbackPlaceholder
                        @unknown default:
                            fallbackPlaceholder
                        }
                    }
                }
            } else {
                fallbackPlaceholder
            }
        }

        @ViewBuilder
        private var metadata: some View {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
            } else if let frameNumberLabel {
                Text(frameNumberLabel)
                    .font(.headline)
                    .foregroundStyle(.white)
            } else {
                EmptyView()
            }
        }

        private var fallbackPlaceholder: some View {
            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.7))
                if let frameNumberLabel {
                    Text(frameNumberLabel)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
    }

    private func attributedString(fromHTML html: String, defaultColor: UIColor? = nil) -> AttributedString? {
        // 1) Preserve line breaks by converting common HTML breaks/blocks to \n
        var text = html
            .replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)

        // Treat common block-level tags as line breaks
        let blockTags = ["</p>", "</div>", "</li>", "</h1>", "</h2>", "</h3>", "</h4>", "</h5>", "</h6>"]
        for tag in blockTags {
            text = text.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }

        // 2) Strip all remaining HTML tags
        // This regex removes anything that looks like <...>
        let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: [])
        let range = NSRange(location: 0, length: (text as NSString).length)
        let stripped = regex?.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "") ?? text

        // 3) Decode basic HTML entities
        let decoded = stripped
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")

        // 4) Collapse multiple consecutive newlines to a single newline
        let collapsed = decoded.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)

        // Return as a plain AttributedString (no styles), letting caller apply font/color
        return AttributedString(collapsed)
    }

    private var descriptionColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var defaultDescriptionUIColor: UIColor {
        .white
    }

    private var aspectRatio: CGFloat {
        guard let ratioString = frame.creativeAspectRatio,
              let parsedRatio = FrameLayout.aspectRatio(from: ratioString) else {
            return 16.0 / 9.0
        }

        return parsedRatio
    }

    private static func aspectRatio(from ratioString: String) -> CGFloat? {
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

    func makeUIView(context _: Context) -> LoopingPlayerView {
        LoopingPlayerView(url: url)
    }

    func updateUIView(_ uiView: LoopingPlayerView, context _: Context) {
        uiView.update(with: url)
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

    init(url: URL) {
        super.init(frame: .zero)
        setupPlayerLayer()
        update(with: url)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupPlayerLayer()
    }

    deinit {
        endObserver.map(NotificationCenter.default.removeObserver)
        queuePlayer?.pause()
        player?.pause()
    }

    func update(with url: URL) {
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
        playerLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(playerLayer)
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

