//
//  LiveActivityManager.swift
//  Martini
//

import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

enum LiveActivityManager {
    static func refresh(using frames: [Frame], projectTitle: String?) {
        guard #available(iOS 16.1, *), !frames.isEmpty else { return }
        Task {
            await refreshActivity(using: frames, projectTitle: projectTitle)
        }
    }

    @available(iOS 16.1, *)
    private static func refreshActivity(using frames: [Frame], projectTitle: String?) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let visibleFrames = frames.filter { !$0.isHidden }
        let sortedFrames = visibleFrames.sorted { $0.frameNumber < $1.frameNumber }
        let currentFrame = sortedFrames.first { $0.statusEnum == .here }
        let nextFrame = sortedFrames.first { $0.statusEnum == .next }

        if currentFrame == nil && nextFrame == nil {
            await endActivitiesIfNeeded()
            return
        }

        let progress = progressCounts(for: visibleFrames)
        let contentState = MartiniLiveActivityAttributes.ContentState(
            currentFrame: currentFrame.map(activityFrame(from:)),
            nextFrame: nextFrame.map(activityFrame(from:)),
            completed: progress.completed,
            total: progress.total
        )

        if let activity = Activity<MartiniLiveActivityAttributes>.activities.first {
            await activity.update(using: contentState)
        } else {
            let attributes = MartiniLiveActivityAttributes(projectTitle: projectTitle ?? "Martini")
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
            number: frame.frameNumber
        )
    }
}
