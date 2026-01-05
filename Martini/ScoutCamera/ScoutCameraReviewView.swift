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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

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

                HStack(spacing: 16) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .buttonStyle(.bordered)

                    Button("Retake") {
                        onRetake()
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task {
                            isPreparingShare = true
                            if let shareImage = await onPrepareShare() {
                                shareItem = ShareItem(image: shareImage)
                            }
                            isPreparingShare = false
                        }
                    } label: {
                        if isPreparingShare {
                            ProgressView()
                        } else {
                            Text("Save/Share")
                        }
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task {
                            isUploading = true
                            await onImport()
                            isUploading = false
                        }
                    } label: {
                        if isUploading {
                            ProgressView()
                        } else {
                            Text("Import")
                        }
                    }
                    .buttonStyle(.borderedProminent)
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

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
