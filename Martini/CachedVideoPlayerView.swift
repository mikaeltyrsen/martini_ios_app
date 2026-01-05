import AVKit
import SwiftUI

struct CachedVideoPlayerView: View {
    let url: URL
    @State private var resolvedURL: URL?

    var body: some View {
        VideoPlayerContainer(url: resolvedURL ?? url)
            .task(id: url) {
                await resolveCachedURL()
            }
    }

    private func resolveCachedURL() async {
        if let cached = VideoCacheManager.shared.existingCachedFile(for: url) {
            resolvedURL = cached
            return
        }

        resolvedURL = url

        let cached = await withCheckedContinuation { continuation in
            VideoCacheManager.shared.fetchCachedURL(for: url) { cachedURL in
                continuation.resume(returning: cachedURL)
            }
        }

        if let cached {
            resolvedURL = cached
        }
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
