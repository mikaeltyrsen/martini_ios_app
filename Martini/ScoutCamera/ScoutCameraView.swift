import SwiftUI
import AVFoundation

struct ScoutCameraView: View {
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ScoutCameraViewModel

    init(projectId: String, frameId: String, targetAspectRatio: CGFloat) {
        _viewModel = StateObject(wrappedValue: ScoutCameraViewModel(projectId: projectId, frameId: frameId, targetAspectRatio: targetAspectRatio))
    }

    var body: some View {
        ZStack {
            CameraPreviewView(session: viewModel.captureManager.session)
                .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                selectorPanel
                captureBar
            }
            .padding()
        }
        .onChange(of: viewModel.selectedCamera) { _ in
            viewModel.refreshModes()
            Task { await viewModel.updateCaptureConfiguration() }
        }
        .onChange(of: viewModel.selectedMode) { _ in
            Task { await viewModel.updateCaptureConfiguration() }
        }
        .onChange(of: viewModel.selectedLens) { _ in
            viewModel.updateFocalLength()
            Task { await viewModel.updateCaptureConfiguration() }
        }
        .onChange(of: viewModel.focalLengthMm) { _ in
            Task { await viewModel.updateCaptureConfiguration() }
        }
        .alert("Scout Camera Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
        .fullScreenCover(isPresented: Binding(
            get: { viewModel.processedImage != nil },
            set: { if !$0 { viewModel.processedImage = nil; viewModel.capturedImage = nil } }
        )) {
            if let image = viewModel.processedImage {
                ScoutCameraReviewView(
                    image: image,
                    onImport: { await handleImport() },
                    onRetake: {
                        viewModel.processedImage = nil
                        viewModel.capturedImage = nil
                    },
                    onCancel: {
                        viewModel.processedImage = nil
                        viewModel.capturedImage = nil
                        dismiss()
                    }
                )
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .foregroundStyle(.white)
            Spacer()
            if let match = viewModel.matchResult {
                Text("\(match.cameraRole.uppercased()) • \(String(format: "%.2fx", match.zoomFactor))")
                    .font(.caption)
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal)
    }

    private var selectorPanel: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Camera")
                Spacer()
                Picker("Camera", selection: $viewModel.selectedCamera) {
                    ForEach(viewModel.availableCameras, id: \.id) { camera in
                        Text("\(camera.brand) \(camera.model)").tag(Optional(camera))
                    }
                }
                .pickerStyle(.menu)
            }

            HStack {
                Text("Mode")
                Spacer()
                Picker("Mode", selection: $viewModel.selectedMode) {
                    ForEach(viewModel.availableModes, id: \.id) { mode in
                        Text(mode.name).tag(Optional(mode))
                    }
                }
                .pickerStyle(.menu)
            }

            HStack {
                Text("Lens")
                Spacer()
                Picker("Lens", selection: $viewModel.selectedLens) {
                    ForEach(viewModel.availableLenses, id: \.id) { lens in
                        Text("\(lens.brand) \(lens.series)").tag(Optional(lens))
                    }
                }
                .pickerStyle(.menu)
            }

            if let lens = viewModel.selectedLens, lens.isZoom {
                VStack(alignment: .leading) {
                    Text("Focal Length: \(Int(viewModel.focalLengthMm))mm")
                        .foregroundStyle(.white)
                    Slider(value: $viewModel.focalLengthMm, in: lens.focalLengthMinMm...lens.focalLengthMaxMm, step: 1)
                }
            }
        }
        .padding()
        .background(.black.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .foregroundStyle(.white)
    }

    private var captureBar: some View {
        HStack {
            Spacer()
            Button {
                viewModel.capturePhoto()
            } label: {
                Circle()
                    .fill(Color.white)
                    .frame(width: 72, height: 72)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.6), lineWidth: 3)
                    )
            }
            Spacer()
        }
        .padding(.bottom, 24)
    }

    private func handleImport() async {
        let success = await viewModel.uploadProcessedImage(token: authService.currentBearerToken())
        if success {
            try? await authService.fetchFrames()
            dismiss()
        }
    }
}

private struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        context.coordinator.previewLayer = previewLayer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.previewLayer?.frame = uiView.bounds
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}
