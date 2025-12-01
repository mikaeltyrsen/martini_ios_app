import ActivityKit
import WidgetKit
import SwiftUI

@main
struct MartiniLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        FrameActivityWidget()
    }
}

struct FrameActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FrameActivityAttributes.self) { context in
            FrameActivityLiveView(context: context)
                .activityBackgroundTint(Color(.secondarySystemBackground))
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    FrameNumberBadge(title: "In Progress", number: context.state.currentFrameNumber)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.attributes.projectName)
                            .font(.headline)
                            .lineLimit(1)
                        ProgressView(value: progressFraction(for: context.state)) {
                            Text(progressLabel(for: context.state))
                                .font(.caption)
                        }
                        .progressViewStyle(.linear)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    if let nextNumber = context.state.upNextFrameNumber {
                        FrameNumberBadge(title: "Up Next", number: nextNumber)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        FrameImageView(imageURL: context.state.currentFrameImageURL)
                            .frame(width: 64, height: 64)
                        if let nextURL = context.state.upNextImageURL, let nextNumber = context.state.upNextFrameNumber {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Up next")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    FrameImageView(imageURL: nextURL)
                                        .frame(width: 48, height: 48)
                                    Text("Frame \(nextNumber)")
                                        .font(.subheadline)
                                }
                            }
                        }
                    }
                }
            } compactLeading: {
                Text("#\(context.state.currentFrameNumber)")
            } compactTrailing: {
                Image(systemName: "film")
            } minimal: {
                Image(systemName: "film")
            }
        }
    }

    private func progressFraction(for state: FrameActivityAttributes.ContentState) -> Double {
        guard state.totalFrames > 0 else { return 0 }
        return Double(state.completedFrames) / Double(state.totalFrames)
    }

    private func progressLabel(for state: FrameActivityAttributes.ContentState) -> String {
        "\(state.completedFrames)/\(state.totalFrames) frames"
    }
}

private struct FrameActivityLiveView: View {
    let context: ActivityViewContext<FrameActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            FrameImageView(imageURL: context.state.currentFrameImageURL)
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 6) {
                Text(context.attributes.projectName)
                    .font(.headline)
                    .lineLimit(1)
                Text("Frame \(context.state.currentFrameNumber) in progress")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProgressView(value: progressFraction)
                    .progressViewStyle(.linear)
            }
        }
        .padding()
    }

    private var progressFraction: Double {
        guard context.state.totalFrames > 0 else { return 0 }
        return Double(context.state.completedFrames) / Double(context.state.totalFrames)
    }
}

private struct FrameNumberBadge: View {
    let title: String
    let number: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Frame \(number)")
                .font(.headline)
        }
    }
}

private struct FrameImageView: View {
    var imageURL: URL?

    var body: some View {
        Group {
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }

    private var placeholder: some View {
        ZStack {
            Color(.tertiarySystemFill)
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
struct FrameActivityWidget_Previews: PreviewProvider {
    static let attributes = FrameActivityAttributes(projectName: "Project Neon")
    static let state = FrameActivityAttributes.ContentState(
        currentFrameNumber: 12,
        currentFrameImageURL: URL(string: "https://images.unsplash.com/photo-1582719478151-1b22902d3d29?w=200"),
        completedFrames: 8,
        totalFrames: 16,
        upNextFrameNumber: 13,
        upNextImageURL: URL(string: "https://images.unsplash.com/photo-1526170375885-4d8ecf77b99f?w=200")
    )

    static var previews: some View {
        FrameActivityLiveView(context: .init(activityAttributes: attributes, contentState: state))
            .previewContext(WidgetPreviewContext(family: .systemMedium))
    }
}
#endif
