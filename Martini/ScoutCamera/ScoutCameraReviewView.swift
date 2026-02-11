import SwiftUI
import UIKit

struct ScoutCameraReviewView: View {
    let image: UIImage
    let frameLineConfigurations: [FrameLineConfiguration]
    let onImport: () async -> Void
    let onPrepareShare: () async -> UIImage?
    let onRetake: () -> Void
    let onCancel: () -> Void

    @State private var isPreparingShare = false
    @State private var shareItem: ShareItem?
    private let actionColor = Color.martiniDefaultColor

    var body: some View {
        ZStack {
            Color(.previewBackground)
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
                GlassEffectContainer(spacing: 20) {
                    HStack(spacing: 24) {
                        ReviewActionButton(
                            title: "Cancel",
                            systemImage: "xmark",
                            //actionColor: Color.martiniRed,
                            hasTint: true,
                            tintColor: Color.red,
                            tintOpacity: 0.2,
                            tintIcon: true,
                            tintIconColor: .red,
                            isLoading: false,
                            action: onCancel
                        )
                        
                        ReviewActionButton(
                            title: "Retake",
                            systemImage: "arrow.clockwise",
                            //actionColor: actionColor,
                            hasTint: false,
                            tintColor: Color.red,
                            tintOpacity: 1,
                            tintIcon: false,
                            tintIconColor: .primary,
                            isLoading: false,
                            action: onRetake
                        )
                        
                        ReviewActionButton(
                            title: "Share",
                            systemImage: "square.and.arrow.up",
                            //actionColor: actionColor,
                            hasTint: false,
                            tintColor: Color.red,
                            tintOpacity: 1,
                            tintIcon: false,
                            tintIconColor: .primary,
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
                            title: "Add Board",
                            systemImage: "photo.badge.plus",
                            //actionColor: actionColor,
                            hasTint: true,
                            tintColor: Color.martiniDefault,
                            tintOpacity: 1,
                            tintIcon: true,
                            tintIconColor: .martiniDefaultText,
                            isLoading: false
                        ) {
                            Task {
                                await onImport()
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
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
    //let actionColor: Color
    let hasTint: Bool
    let tintColor: Color
    let tintOpacity: CGFloat
    let tintIcon: Bool
    let tintIconColor: Color
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {

                ZStack {
                    if isLoading {
                        MartiniLoader()
                            .font(.system(size: 25))
                            .tint(tintIcon ? tintIconColor : .primary)
                    } else {
                        Image(systemName: systemImage)
                            .font(.system(size: 25))
                    }
                }
                .frame(width: 60, height: 60)
                .foregroundStyle(tintIcon ? tintIconColor : .primary)
                .glassEffect(
                    .regular.tint(hasTint ? tintColor.opacity(hasTint ? tintOpacity : 1) : nil).interactive(),
                    in: Circle()
                )
                    
                Text(title)
                    .font(.caption2)
                    .opacity(0.60)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
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
