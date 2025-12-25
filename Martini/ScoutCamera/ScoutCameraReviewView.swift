import SwiftUI

struct ScoutCameraReviewView: View {
    let image: UIImage
    let onImport: () async -> Void
    let onRetake: () -> Void
    let onCancel: () -> Void

    @State private var isUploading = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(12)
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
    }
}
