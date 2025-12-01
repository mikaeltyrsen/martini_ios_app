#if canImport(ActivityKit)
import ActivityKit
import Foundation

@available(iOS 16.1, *)
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var activity: Activity<FrameActivityAttributes>?

    private init() {}

    func sync(using authService: AuthService) {
        guard #available(iOS 16.1, *),
              ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        Task { @MainActor in
            guard let currentFrame = currentInProgressFrame(from: authService.frames) else {
                await endActivityIfNeeded()
                return
            }

            let upNextFrame = nextFrame(from: authService.frames)
            let contentState = FrameActivityAttributes.ContentState(
                currentFrameNumber: currentFrame.frameNumber,
                currentFrameImageURL: thumbnailURL(for: currentFrame),
                completedFrames: totalCompletedFrames(from: authService.creatives),
                totalFrames: totalFrameCount(from: authService.creatives),
                upNextFrameNumber: upNextFrame?.frameNumber,
                upNextImageURL: thumbnailURL(for: upNextFrame)
            )

            let attributes = FrameActivityAttributes(projectName: authService.projectTitle ?? authService.projectId ?? "Martini")

            if let activity {
                await activity.update(using: contentState)
            } else {
                do {
                    activity = try Activity.request(attributes: attributes, contentState: contentState, pushType: nil)
                } catch {
                    print("Failed to start live activity: \(error.localizedDescription)")
                }
            }
        }
    }

    func endIfNeeded() {
        guard #available(iOS 16.1, *), ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        Task { await endActivityIfNeeded() }
    }

    @MainActor
    private func endActivityIfNeeded() async {
        guard let activity else { return }
        await activity.end(dismissalPolicy: .immediate)
        self.activity = nil
    }

    private func currentInProgressFrame(from frames: [Frame]) -> Frame? {
        frames
            .filter { $0.statusEnum == .inProgress }
            .sorted { $0.frameNumber < $1.frameNumber }
            .first
    }

    private func nextFrame(from frames: [Frame]) -> Frame? {
        frames
            .filter { $0.statusEnum == .upNext }
            .sorted { $0.frameNumber < $1.frameNumber }
            .first
    }

    private func thumbnailURL(for frame: Frame?) -> URL? {
        guard let frame else { return nil }
        let urlString =
            frame.previewThumb ??
            frame.captureClipThumbnail ??
            frame.photoboardThumb ??
            frame.preview ??
            frame.captureClip ??
            frame.photoboard ??
            frame.boardThumb ??
            frame.board
        guard let urlString, let url = URL(string: urlString) else { return nil }
        return url
    }

    private func totalCompletedFrames(from creatives: [Creative]) -> Int {
        creatives.reduce(0) { $0 + $1.completedFrames }
    }

    private func totalFrameCount(from creatives: [Creative]) -> Int {
        creatives.reduce(0) { $0 + $1.totalFrames }
    }
}
#endif
