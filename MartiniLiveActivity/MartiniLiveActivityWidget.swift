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
                    Image(systemName: "photo")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(.white)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    LiveActivityFrameProgressBadge(
                        currentFrame: context.state.currentFrame,
                        nextFrame: context.state.nextFrame,
                        completed: context.state.completed,
                        total: context.state.total,
                        size: 44
                    )
                }

                DynamicIslandExpandedRegion(.bottom) {
                    LiveActivityProgressView(completed: context.state.completed, total: context.state.total)
                }
            } compactLeading: {
                ZStack {
                        Color.clear // keeps layout stable
                        Image("MartiniLogoIconOnly")
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } compactTrailing: {
                LiveActivityFrameProgressBadge(
                    currentFrame: context.state.currentFrame,
                    nextFrame: context.state.nextFrame,
                    completed: context.state.completed,
                    total: context.state.total,
                    size: 24
                )
            } minimal: {
                ZStack {
                        Color.clear // keeps layout stable
                        Image("MartiniLogoIconOnly")
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }
}

@available(iOS 16.1, *)
private struct LiveActivityView: View {
    let context: ActivityViewContext<MartiniLiveActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack() {
                VStack(alignment: .leading, spacing: 6) {
                    Image("MartiniLogo")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 70, alignment: .leading)
                        .foregroundStyle(.primary)
                    
                    Text(context.attributes.projectTitle)
                        .font(.system(size: 20, weight: .semibold, design: .default))
                        .foregroundColor(.primary)
                }
                
                HStack(spacing: 10) {
                    LiveActivityFrameLabel(
                        label: "Current",
                        frame: context.state.currentFrame,
                        borderColor: .green,
                        iconName: "video.fill"
                    )
                    LiveActivityFrameLabel(
                        label: "Next",
                        frame: context.state.nextFrame,
                        borderColor: .orange,
                        iconName: "forward.fill"
                    )
                }
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
    let iconName: String

    private let thumbnailSize: CGFloat = 92

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(borderColor)
                
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(borderColor)
            }
            .frame(width: thumbnailSize, alignment: .leading)
            if let frame {
                LiveActivityFrameThumbnail(frame: frame, borderColor: borderColor, size: thumbnailSize)
            } else {
                LiveActivityFrameThumbnail(frame: nil, borderColor: borderColor, size: thumbnailSize)
            }
        }
    }
}

@available(iOS 16.1, *)
private struct LiveActivityProgressView: View {
    let completed: Int
    let total: Int

    struct ThickProgressViewStyle: ProgressViewStyle {
        var height: CGFloat = 20
        var cornerRadius: CGFloat = 100
        
        func makeBody(configuration: Configuration) -> some View {
            GeometryReader { geo in
                let fraction = CGFloat(configuration.fractionCompleted ?? 0)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: height)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.primary)
                        .frame(width: geo.size.width * fraction, height: height)
                }
            }
        }
    }
    
    var body: some View {
        let safeTotal = max(total, 1)

        HStack(spacing: 8) {

            Text("\(completed)")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(height: 20)

            ProgressView(value: Double(completed), total: Double(safeTotal))
                .progressViewStyle(ThickProgressViewStyle(height: 20))
                .frame(height: 20)

            Text("\(total)")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(height: 20)
        }
    }
}

@available(iOS 16.1, *)
private struct LiveActivityFrameThumbnail: View {
    let frame: MartiniLiveActivityFrame?
    let borderColor: Color
    let size: CGFloat

    private let cornerRadius = 8.0
    private let borderWidth = 2.0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            thumbnailView
                .frame(width: size, height: size, alignment: .leading)
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
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
private struct LiveActivityFrameProgressBadge: View {
    let currentFrame: MartiniLiveActivityFrame?
    let nextFrame: MartiniLiveActivityFrame?
    let completed: Int
    let total: Int
    let size: CGFloat

    var body: some View {
        let safeTotal = max(total, 1)
        let progress = min(max(Double(completed) / Double(safeTotal), 0), 1)

        ZStack {
            Circle()
                .stroke(activeColor.opacity(0.15), lineWidth: size * 0.14)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    activeColor.opacity(1),
                    style: StrokeStyle(lineWidth: size * 0.14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text(progressLabel)
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(activeColor)
                .minimumScaleFactor(0.5)
        }
        .frame(width: size, height: size)
        .padding(2)
    }

    private var progressLabel: String {
        if completed > 0 {
            return String(completed)
        }
        guard let frame, frame.number > 0 else { return "-" }
        return String(frame.number)
    }

    private var activeColor: Color {
        if currentFrame?.number ?? 0 > 0 {
            return .green
        }
        if nextFrame?.number ?? 0 > 0 {
            return .orange
        }
        return .gray
    }

    private var frame: MartiniLiveActivityFrame? {
        currentFrame ?? nextFrame
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

#if DEBUG
@available(iOS 16.1, *)
#Preview("Live Activity", as: .content, using: previewAttributes) {
    MartiniLiveActivityWidget()
} contentStates: {
    previewContentState
}

@available(iOS 16.1, *)
#Preview("Dynamic Island Expanded", as: .dynamicIsland(.expanded), using: previewAttributes) {
    MartiniLiveActivityWidget()
} contentStates: {
    previewContentState
}

@available(iOS 16.1, *)
#Preview("Dynamic Island Compact", as: .dynamicIsland(.compact), using: previewAttributes) {
    MartiniLiveActivityWidget()
} contentStates: {
    previewContentState
}

@available(iOS 16.1, *)
#Preview("Dynamic Island Minimal", as: .dynamicIsland(.minimal), using: previewAttributes) {
    MartiniLiveActivityWidget()
} contentStates: {
    previewContentState
}

@available(iOS 16.1, *)
private var previewAttributes: MartiniLiveActivityAttributes {
    MartiniLiveActivityAttributes(projectTitle: "Espresso Sprint")
}

@available(iOS 16.1, *)
private var previewContentState: MartiniLiveActivityAttributes.ContentState {
    MartiniLiveActivityAttributes.ContentState(
        currentFrame: MartiniLiveActivityFrame(
            id: "frame-12",
            title: "Storyboard",
            number: 12,
            thumbnailUrl: nil
        ),
        nextFrame: MartiniLiveActivityFrame(
            id: "frame-13",
            title: "Animatic",
            number: 13,
            thumbnailUrl: nil
        ),
        completed: 12,
        total: 48
    )
}
#endif
