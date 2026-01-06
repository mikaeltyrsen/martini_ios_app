import SwiftUI
import UIKit

struct ScoutCameraReviewView: View {
    let image: UIImage
    let frameLineConfigurations: [FrameLineConfiguration]
    let onImport: () async -> Void
    let onPrepareShare: () async -> UIImage?
    let onRetake: () -> Void
    let onCancel: () -> Void

    @State private var isUploading = false
    @State private var isPreparingShare = false
    @State private var shareItem: ShareItem?
    private let actionColor = Color.martiniDefaultColor

    var body: some View {
        ZStack {
            Color(.systemBackground)
                    .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(12)
                    .overlay {
                        if !frameLineConfigurations.isEmpty {
                            FrameLineOverlayView(configurations: frameLineConfigurations)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding()

                HStack(spacing: 24) {
                    ReviewActionButton(
                        title: "Cancel",
                        systemImage: "xmark",
                        actionColor: Color.martiniRed,
                        isHighlighted: false,
                        isLoading: false,
                        action: onCancel
                    )

                    ReviewActionButton(
                        title: "Retake",
                        systemImage: "arrow.clockwise",
                        actionColor: actionColor,
                        isHighlighted: false,
                        isLoading: false,
                        action: onRetake
                    )

                    ReviewActionButton(
                        title: "Share",
                        systemImage: "square.and.arrow.up",
                        actionColor: actionColor,
                        isHighlighted: false,
                        isLoading: isPreparingShare
                    ) {
                        Task {
                            isPreparingShare = true
                            if let shareImage = await onPrepareShare() {
                                shareItem = ShareItem(image: shareImage)
                            }
                            isPreparingShare = false
                        }
                    }
                    .disabled(isPreparingShare)

                    ReviewActionButton(
                        title: "Import",
                        systemImage: "square.and.arrow.down",
                        actionColor: actionColor,
                        isHighlighted: true,
                        isLoading: isUploading
                    ) {
                        Task {
                            isUploading = true
                            await onImport()
                            isUploading = false
                        }
                    }
                    .disabled(isUploading)
                }
                .padding(.bottom, 24)
            }
        }
        .sheet(item: $shareItem) { item in
            ActivityView(activityItems: [item.image])
        }
        .interactiveDismissDisabled(true)
    }
}

private struct ShareItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct ReviewActionButton: View {
    let title: String
    let systemImage: String
    let actionColor: Color
    let isHighlighted: Bool
    let isLoading: Bool
    let action: () -> Void

    private let circleSize: CGFloat = 60
    private let iconSize: CGFloat = 24
    private let normalBackgroundOpacity: Double = 0.18
    private let highlightedBackgroundOpacity: Double = 1

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    actionColor.opacity(isHighlighted ? 0.70 : 0.30),
                                    actionColor.opacity(isHighlighted ? 0.50 : 0.10)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: circleSize, height: circleSize)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            actionColor.opacity(isHighlighted ? 0.70 : 0.30),
                                            actionColor.opacity(isHighlighted ? 0.40 : 0.20)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.35),
                                            .clear
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 0.5
                                )
                        )

//                    Circle()
//                        .fill(actionColor.opacity(isHighlighted ? highlightedBackgroundOpacity : normalBackgroundOpacity))
//                        .frame(width: circleSize, height: circleSize)
//                        .overlay(
//                            Circle()
//                                .stroke(actionColor.opacity(isHighlighted ? 0.6 : 0.4), lineWidth: 1)
//                        )

                    if isLoading {
                        ProgressView()
                            .tint(actionColor)
                    } else {
                        Image(systemName: systemImage)
                            .font(.system(size: iconSize, weight: .semibold))
                            .foregroundStyle(isHighlighted ? Color.white : actionColor)
                    }
                }

                Text(title)
                    .font(.caption2)
                    .foregroundStyle(actionColor)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
