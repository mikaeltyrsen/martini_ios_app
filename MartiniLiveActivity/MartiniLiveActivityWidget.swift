//
//  MartiniLiveActivityWidget.swift
//  MartiniLiveActivity
//

import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 16.1, *)
struct MartiniLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MartiniLiveActivityAttributes.self) { context in
            LiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LiveActivityFrameLabel(label: "Now", frame: context.state.currentFrame)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    LiveActivityFrameLabel(label: "Next", frame: context.state.nextFrame)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    LiveActivityProgressView(completed: context.state.completed, total: context.state.total)
                }
            } compactLeading: {
                LiveActivityCompactFrameBadge(label: "N", frame: context.state.currentFrame)
            } compactTrailing: {
                LiveActivityCompactFrameBadge(label: "X", frame: context.state.nextFrame)
            } minimal: {
                LiveActivityMinimalBadge(frame: context.state.currentFrame ?? context.state.nextFrame)
            }
        }
    }
}

@available(iOS 16.1, *)
private struct LiveActivityView: View {
    let context: ActivityViewContext<MartiniLiveActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(context.attributes.projectTitle)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                LiveActivityFrameLabel(label: "Current", frame: context.state.currentFrame)
                LiveActivityFrameLabel(label: "Next", frame: context.state.nextFrame)
            }

            LiveActivityProgressView(completed: context.state.completed, total: context.state.total)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

@available(iOS 16.1, *)
private struct LiveActivityFrameLabel: View {
    let label: String
    let frame: MartiniLiveActivityFrame?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: 54, alignment: .leading)

            if let frame {
                Text(frameTitle(frame))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            } else {
                Text("—")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func frameTitle(_ frame: MartiniLiveActivityFrame) -> String {
        if frame.number > 0 {
            return "\(frame.number). \(frame.title)"
        }
        return frame.title
    }
}

@available(iOS 16.1, *)
private struct LiveActivityProgressView: View {
    let completed: Int
    let total: Int

    var body: some View {
        let safeTotal = max(total, 1)

        HStack(spacing: 8) {
            Text("\(completed)")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            ProgressView(value: Double(completed), total: Double(safeTotal))
                .tint(.accentColor)

            Text("\(total)")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
        }
    }
}

@available(iOS 16.1, *)
private struct LiveActivityCompactFrameBadge: View {
    let label: String
    let frame: MartiniLiveActivityFrame?

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)

            Text(frameNumber)
                .font(.caption.weight(.semibold))
        }
    }

    private var frameNumber: String {
        guard let frame, frame.number > 0 else { return "-" }
        return String(frame.number)
    }
}

@available(iOS 16.1, *)
private struct LiveActivityMinimalBadge: View {
    let frame: MartiniLiveActivityFrame?

    var body: some View {
        Text(frameNumber)
            .font(.caption.weight(.semibold))
    }

    private var frameNumber: String {
        guard let frame, frame.number > 0 else { return "-" }
        return String(frame.number)
    }
}
