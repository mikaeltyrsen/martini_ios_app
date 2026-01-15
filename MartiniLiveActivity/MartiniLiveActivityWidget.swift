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
                    LiveActivityFrameLabel(
                        label: "Now",
                        frame: context.state.currentFrame,
                        borderColor: .green
                    )
                }

                DynamicIslandExpandedRegion(.trailing) {
                    LiveActivityFrameLabel(
                        label: "Next",
                        frame: context.state.nextFrame,
                        borderColor: .orange
                    )
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
                LiveActivityFrameLabel(
                    label: "Current",
                    frame: context.state.currentFrame,
                    borderColor: .green
                )
                LiveActivityFrameLabel(
                    label: "Next",
                    frame: context.state.nextFrame,
                    borderColor: .orange
                )
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
    let borderColor: Color

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: 54, alignment: .leading)

            if let frame {
                LiveActivityFrameThumbnail(frame: frame, borderColor: borderColor)
            } else {
                LiveActivityFrameThumbnail(frame: nil, borderColor: borderColor)
            }
        }
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
private struct LiveActivityFrameThumbnail: View {
    let frame: MartiniLiveActivityFrame?
    let borderColor: Color

    private let size = CGSize(width: 92, height: 52)
    private let cornerRadius = 8.0
    private let borderWidth = 2.0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            thumbnailView
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(borderColor, lineWidth: borderWidth)
                )

            if let numberText = frameNumberText {
                Text(numberText)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.black.opacity(0.8))
                    .clipShape(Circle())
                    .padding(4)
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let url = thumbnailUrl {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholderView
                case .empty:
                    placeholderView
                @unknown default:
                    placeholderView
                }
            }
        } else {
            placeholderView
        }
    }

    private var placeholderView: some View {
        ZStack {
            Color.secondary.opacity(0.2)
            Image(systemName: "photo")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var frameNumberText: String? {
        guard let frame, frame.number > 0 else { return nil }
        return String(frame.number)
    }

    private var thumbnailUrl: URL? {
        guard let urlString = frame?.thumbnailUrl else { return nil }
        return URL(string: urlString)
    }

    private var accessibilityLabel: String {
        guard let frame else { return "No frame" }
        if frame.number > 0 {
            return "Frame \(frame.number), \(frame.title)"
        }
        return frame.title
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
