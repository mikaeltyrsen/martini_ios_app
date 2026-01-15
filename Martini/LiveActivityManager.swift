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
        let currentFrame = sortedFrames.first { $0.statusEnum == .here }
        let nextFrame = sortedFrames.first { $0.statusEnum == .next }

        let resolvedTitle = projectTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = (resolvedTitle?.isEmpty == false) ? resolvedTitle! : "Martini"

        let progress = progressCounts(for: frames)
        let contentState = MartiniLiveActivityAttributes.ContentState(
            currentFrame: currentFrame.map(activityFrame(from:)),
            nextFrame: nextFrame.map(activityFrame(from:)),
            completed: progress.completed,
            total: progress.total
        )

        if let activity = Activity<MartiniLiveActivityAttributes>.activities.first {
            if activity.attributes.projectTitle == displayTitle {
                await activity.update(using: contentState)
                return
            }

            await activity.end(nil, dismissalPolicy: .immediate)
        }

        guard await isAppActiveForNewActivity() else { return }

        let attributes = MartiniLiveActivityAttributes(projectTitle: displayTitle)
        do {
            _ = try Activity.request(
                attributes: attributes,
                contentState: contentState,
                pushType: nil
            )
        } catch {
            return
        }
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
        } else if frame.frameNumber > 0 {
            displayTitle = "Frame \(frame.frameNumber)"
        } else {
            displayTitle = "Frame"
        }

        return MartiniLiveActivityFrame(
            id: frame.id,
            title: displayTitle,
            number: frame.frameNumber,
            thumbnailUrl: frameThumbnailUrl(for: frame)
        )
    }

    private static func storyOrderSort(_ lhs: Frame, _ rhs: Frame) -> Bool {
        let leftOrder = storyOrderValue(for: lhs)
        let rightOrder = storyOrderValue(for: rhs)
        if leftOrder != rightOrder {
            return leftOrder < rightOrder
        }
        return lhs.frameNumber < rhs.frameNumber
    }

    private static func storyOrderValue(for frame: Frame) -> Int {
        if let order = frame.frameOrder, let value = Int(order) {
            return value
        }
        return Int.max
    }

    private static func frameThumbnailUrl(for frame: Frame) -> String? {
        let boardAsset = frame.availableAssets.first { $0.kind == .board }
        if let thumbnailUrl = boardAsset?.thumbnailURL?.absoluteString {
            return thumbnailUrl
        }
        if let url = boardAsset?.url?.absoluteString {
            return url
        }

        let fallbackAsset = frame.availableAssets.first
        if let thumbnailUrl = fallbackAsset?.thumbnailURL?.absoluteString {
            return thumbnailUrl
        }
        if let url = fallbackAsset?.url?.absoluteString {
            return url
        }

        return frame.boardThumb
            ?? frame.previewThumb
            ?? frame.photoboardThumb
            ?? frame.captureClipThumbnail
            ?? frame.board
            ?? frame.preview
            ?? frame.photoboard
            ?? frame.captureClip
    }
}
