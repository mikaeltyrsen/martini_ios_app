//
//  LiveActivityManager.swift
//  Martini
//

import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif
#if canImport(UIKit)
import UIKit
#endif

enum LiveActivityManager {
    private static let isDebugLoggingEnabled = true

    static func refresh(using frames: [Frame], projectTitle: String?, isInProject: Bool) {
        guard #available(iOS 16.1, *) else { return }
        Task {
            await refreshActivity(using: frames, projectTitle: projectTitle, isInProject: isInProject)
        }
    }

    @available(iOS 16.1, *)
    private static func refreshActivity(using frames: [Frame], projectTitle: String?, isInProject: Bool) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        guard isInProject else {
            await endActivitiesIfNeeded()
            return
        }

        let sortedFrames = frames.sorted(by: storyOrderSort)
        let visibleFrames = sortedFrames.filter { !$0.isHidden }
        let statusCurrentFrame = sortedFrames.first { $0.statusEnum == .here }
        let statusNextFrame = sortedFrames.first { $0.statusEnum == .next }
        var currentFrame = statusCurrentFrame
        var nextFrame = statusNextFrame

        if currentFrame != nil && nextFrame == nil {
            nextFrame = nextVisibleFrame(after: currentFrame, in: visibleFrames)
        }

        if currentFrame == nil && nextFrame == nil {
            nextFrame = nextVisibleFrame(after: nil, in: visibleFrames)
        }

        if currentFrame?.id == nextFrame?.id {
            nextFrame = nil
        }

        logDebugFrameSelection(
            totalFrames: frames.count,
            visibleFrames: visibleFrames.count,
            statusCurrentFrame: statusCurrentFrame,
            statusNextFrame: statusNextFrame,
            currentFrame: currentFrame,
            nextFrame: nextFrame
        )

        let resolvedTitle = projectTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = (resolvedTitle?.isEmpty == false) ? resolvedTitle! : "Martini"

        let progress = progressCounts(for: frames)
        let contentState = MartiniLiveActivityAttributes.ContentState(
            currentFrame: currentFrame.map(activityFrame(from:)),
            nextFrame: nextFrame.map(activityFrame(from:)),
            completed: progress.completed,
            total: progress.total
        )

        logDebugActivityState(
            projectTitle: displayTitle,
            contentState: contentState
        )

        if let activity = Activity<MartiniLiveActivityAttributes>.activities.first {
            if activity.attributes.projectTitle == displayTitle {
                logDebugActivityPush(action: "update", contentState: contentState)
                await activity.update(using: contentState)
                return
            }

            if isDebugLoggingEnabled {
                print("🧩 LiveActivity end: title mismatch existing=\(activity.attributes.projectTitle) new=\(displayTitle)")
            }
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        guard await isAppActiveForNewActivity() else { return }

        let attributes = MartiniLiveActivityAttributes(projectTitle: displayTitle)
        do {
            logDebugActivityPush(action: "request", contentState: contentState)
            _ = try Activity.request(
                attributes: attributes,
                contentState: contentState,
                pushType: nil
            )
        } catch {
            return
        }
    }

    private static func nextVisibleFrame(after currentFrame: Frame?, in frames: [Frame]) -> Frame? {
        guard let currentFrame else {
            return frames.first
        }
        guard let currentIndex = frames.firstIndex(where: { $0.id == currentFrame.id }) else {
            return frames.first
        }
        let nextIndex = frames.index(after: currentIndex)
        guard nextIndex < frames.endIndex else { return nil }
        return frames[nextIndex]
    }

    @available(iOS 16.1, *)
    private static func isAppActiveForNewActivity() async -> Bool {
#if canImport(UIKit)
        return await MainActor.run {
            UIApplication.shared.applicationState == .active
        }
#else
        return true
#endif
    }

    @available(iOS 16.1, *)
    private static func endActivitiesIfNeeded() async {
        for activity in Activity<MartiniLiveActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private static func activityFrame(from frame: Frame) -> MartiniLiveActivityFrame {
        let displayTitle: String
        if let caption = frame.caption, !caption.isEmpty {
            displayTitle = caption
        } else if let description = frame.description, !description.isEmpty {
            displayTitle = description
        } else if let displayOrder = frame.displayOrder, !displayOrder.isEmpty {
            displayTitle = "Frame \(displayOrder)"
        } else {
            displayTitle = "Frame"
        }

        let thumbnailSelection = frameThumbnailSelection(for: frame)

        return MartiniLiveActivityFrame(
            id: frame.id,
            title: displayTitle,
            number: frame.frameNumber,
            thumbnailUrl: thumbnailSelection.url,
            creativeAspectRatio: frame.creativeAspectRatio,
            crop: thumbnailSelection.crop
        )
    }

    private static func storyOrderSort(_ lhs: Frame, _ rhs: Frame) -> Bool {
        let leftOrder = FrameOrderKey.from(lhs.frameOrder)
        let rightOrder = FrameOrderKey.from(rhs.frameOrder)
        if leftOrder != rightOrder {
            return leftOrder < rightOrder
        }
        return FrameOrderKey.from(lhs.frameShootOrder) < FrameOrderKey.from(rhs.frameShootOrder)
    }

    private struct ThumbnailSelection {
        let url: String?
        let crop: String?
        let source: String
    }

    private static func frameThumbnailSelection(for frame: Frame) -> ThumbnailSelection {
        let boardAsset = frame.availableAssets.first { $0.kind == .board }
        if let thumbnailUrl = boardAsset?.thumbnailURL?.absoluteString {
            logDebugThumbnail(frame: frame, source: "boardAsset.thumbnailURL", url: thumbnailUrl)
            return ThumbnailSelection(
                url: thumbnailUrl,
                crop: cropValue(for: boardAsset, in: frame),
                source: "boardAsset.thumbnailURL"
            )
        }
        if let url = boardAsset?.url?.absoluteString {
            logDebugThumbnail(frame: frame, source: "boardAsset.url", url: url)
            return ThumbnailSelection(
                url: url,
                crop: cropValue(for: boardAsset, in: frame),
                source: "boardAsset.url"
            )
        }

        let fallbackAsset = frame.availableAssets.first
        if let thumbnailUrl = fallbackAsset?.thumbnailURL?.absoluteString {
            logDebugThumbnail(frame: frame, source: "fallbackAsset.thumbnailURL", url: thumbnailUrl)
            return ThumbnailSelection(
                url: thumbnailUrl,
                crop: cropValue(for: fallbackAsset, in: frame),
                source: "fallbackAsset.thumbnailURL"
            )
        }
        if let url = fallbackAsset?.url?.absoluteString {
            logDebugThumbnail(frame: frame, source: "fallbackAsset.url", url: url)
            return ThumbnailSelection(
                url: url,
                crop: cropValue(for: fallbackAsset, in: frame),
                source: "fallbackAsset.url"
            )
        }

        let fallbackUrl = frame.boardThumb
            ?? frame.previewThumb
            ?? frame.photoboardThumb
            ?? frame.captureClipThumbnail
            ?? frame.board
            ?? frame.preview
            ?? frame.photoboard
            ?? frame.captureClip

        if let fallbackUrl {
            logDebugThumbnail(frame: frame, source: "frame.fallback", url: fallbackUrl)
            return ThumbnailSelection(
                url: fallbackUrl,
                crop: frameFallbackCrop(for: frame),
                source: "frame.fallback"
            )
        }
        logDebugThumbnail(frame: frame, source: "frame.fallback", url: nil)

        return ThumbnailSelection(url: nil, crop: nil, source: "frame.fallback")
    }

    private static func cropValue(for asset: FrameAssetItem?, in frame: Frame) -> String? {
        guard let asset else { return nil }
        switch asset.id {
        case "photoboard":
            return frame.photoboardCrop ?? frame.crop
        case "preview":
            return frame.previewCrop ?? frame.crop
        case "captureClip":
            return frame.captureClipCrop ?? frame.crop
        case "board-main":
            return frame.crop
        default:
            if asset.kind == .board {
                let boardCrop = frame.boards?.first(where: { $0.id == asset.id })?.fileCrop
                return boardCrop ?? frame.crop
            }
        }
        return frame.crop
    }

    private static func frameFallbackCrop(for frame: Frame) -> String? {
        if frame.boardThumb != nil || frame.board != nil {
            return frame.crop
        }
        if frame.previewThumb != nil || frame.preview != nil {
            return frame.previewCrop ?? frame.crop
        }
        if frame.photoboardThumb != nil || frame.photoboard != nil {
            return frame.photoboardCrop ?? frame.crop
        }
        if frame.captureClipThumbnail != nil || frame.captureClip != nil {
            return frame.captureClipCrop ?? frame.crop
        }
        return frame.crop
    }

    private static func logDebugFrameSelection(
        totalFrames: Int,
        visibleFrames: Int,
        statusCurrentFrame: Frame?,
        statusNextFrame: Frame?,
        currentFrame: Frame?,
        nextFrame: Frame?
    ) {
        guard isDebugLoggingEnabled else { return }
        print("🧩 LiveActivity selection: total=\(totalFrames) visible=\(visibleFrames)")
        print("🧩 LiveActivity status current=\(statusCurrentFrame?.id ?? "nil") next=\(statusNextFrame?.id ?? "nil")")
        print("🧩 LiveActivity resolved current=\(currentFrame?.id ?? "nil") next=\(nextFrame?.id ?? "nil")")
        logDebugFrameDetails(label: "statusCurrent", frame: statusCurrentFrame)
        logDebugFrameDetails(label: "statusNext", frame: statusNextFrame)
        logDebugFrameDetails(label: "current", frame: currentFrame)
        logDebugFrameDetails(label: "next", frame: nextFrame)
    }

    private static func logDebugActivityState(
        projectTitle: String,
        contentState: MartiniLiveActivityAttributes.ContentState
    ) {
        guard isDebugLoggingEnabled else { return }
        let currentThumb = contentState.currentFrame?.thumbnailUrl ?? "nil"
        let nextThumb = contentState.nextFrame?.thumbnailUrl ?? "nil"
        print("🧩 LiveActivity state: title=\(projectTitle) completed=\(contentState.completed) total=\(contentState.total)")
        print("🧩 LiveActivity thumbnails: current=\(currentThumb) next=\(nextThumb)")
        print("🧩 LiveActivity currentFrame: \(activityFrameSummary(contentState.currentFrame))")
        print("🧩 LiveActivity nextFrame: \(activityFrameSummary(contentState.nextFrame))")
    }

    private static func logDebugThumbnail(frame: Frame, source: String, url: String?) {
        guard isDebugLoggingEnabled else { return }
        print("🧩 LiveActivity thumbnail: frame=\(frame.id) source=\(source) url=\(url ?? "nil")")
    }

    private static func logDebugActivityPush(
        action: String,
        contentState: MartiniLiveActivityAttributes.ContentState
    ) {
        guard isDebugLoggingEnabled else { return }
        print("🧩 LiveActivity push=\(action) current=\(activityFrameSummary(contentState.currentFrame)) next=\(activityFrameSummary(contentState.nextFrame))")
    }

    private static func logDebugFrameDetails(label: String, frame: Frame?) {
        guard isDebugLoggingEnabled else { return }
        guard let frame else {
            print("🧩 LiveActivity \(label): nil")
            return
        }
        print("🧩 LiveActivity \(label): id=\(frame.id) number=\(frame.frameNumber) status=\(frame.statusEnum.rawValue) hidden=\(frame.isHidden)")
        print("🧩 LiveActivity \(label) assets: \(assetSummary(for: frame))")
        let candidateSummary = imageCandidateSummary(for: frame)
        print("🧩 LiveActivity \(label) images: \(candidateSummary)")
    }

    private static func activityFrameSummary(_ frame: MartiniLiveActivityFrame?) -> String {
        guard let frame else { return "nil" }
        let thumbnail = frame.thumbnailUrl ?? "nil"
        return "id=\(frame.id) number=\(frame.number) title=\(frame.title) thumb=\(thumbnail)"
    }

    private static func assetSummary(for frame: Frame) -> String {
        let assets = frame.availableAssets
        guard !assets.isEmpty else { return "none" }
        let limit = 3
        let summaries = assets.prefix(limit).map { asset in
            let url = asset.url?.absoluteString ?? "nil"
            let thumb = asset.thumbnailURL?.absoluteString ?? "nil"
            return "\(asset.kind.rawValue):url=\(url) thumb=\(thumb)"
        }
        let suffix = assets.count > limit ? " | +\(assets.count - limit) more" : ""
        return summaries.joined(separator: " | ") + suffix
    }

    private static func imageCandidateSummary(for frame: Frame) -> String {
        let candidates: [(String, String?)] = [
            ("boardThumb", frame.boardThumb),
            ("previewThumb", frame.previewThumb),
            ("photoboardThumb", frame.photoboardThumb),
            ("captureClipThumbnail", frame.captureClipThumbnail),
            ("board", frame.board),
            ("preview", frame.preview),
            ("photoboard", frame.photoboard),
            ("captureClip", frame.captureClip)
        ]
        let entries = candidates.compactMap { label, value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return "\(label)=\(value)"
        }
        return entries.isEmpty ? "none" : entries.joined(separator: " | ")
    }
}
