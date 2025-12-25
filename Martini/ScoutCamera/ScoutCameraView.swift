import SwiftUI
import AVFoundation
import UIKit

struct ScoutCameraView: View {
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ScoutCameraViewModel
    @StateObject private var motionManager = MotionHeadingManager()
    private let targetAspectRatio: CGFloat

    init(projectId: String, frameId: String, targetAspectRatio: CGFloat) {
        self.targetAspectRatio = targetAspectRatio
        _viewModel = StateObject(wrappedValue: ScoutCameraViewModel(projectId: projectId, frameId: frameId, targetAspectRatio: targetAspectRatio))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                topBar
                headingBar
                previewPanel
                selectorPanel
                captureBar
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .onAppear {
            UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
            motionManager.start()
        }
        .onDisappear {
            motionManager.stop()
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

            HStack {
                Text("Frame Lines")
                Spacer()
                Picker("Frame Lines", selection: $viewModel.selectedFrameLine) {
                    ForEach(FrameLineOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }

            if let lens = viewModel.selectedLens, lens.isZoom,
               let minFocal = lens.focalLengthMinMm, let maxFocal = lens.focalLengthMaxMm {
                VStack(alignment: .leading) {
                    Text("Focal Length: \(Int(viewModel.focalLengthMm))mm")
                        .foregroundStyle(.white)
                    Slider(value: $viewModel.focalLengthMm, in: minFocal...maxFocal, step: 1)
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

    private var headingBar: some View {
        HStack {
            Text("\(motionManager.headingText) \(Int(motionManager.headingDegrees))°")
            Spacer()
            Text("Tilt \(Int(motionManager.tiltDegrees))°")
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(.horizontal)
    }

    private var previewPanel: some View {
        GeometryReader { proxy in
            ZStack {
                CameraPreviewView(session: viewModel.captureManager.session)
                    .aspectRatio(targetAspectRatio, contentMode: .fit)
                    .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)

                if let frameLineAspect = viewModel.selectedFrameLine.aspectRatio {
                    FrameLineOverlay(aspectRatio: frameLineAspect)
                        .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height)
                }
            }
        }
        .aspectRatio(targetAspectRatio, contentMode: .fit)
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
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.setVideoOrientation(.landscapeRight)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let previewView = uiView as? PreviewView else { return }
        previewView.videoPreviewLayer.session = session
        previewView.setVideoOrientation(.landscapeRight)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

private struct FrameLineOverlay: View {
    let aspectRatio: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let rect = frameRect(in: proxy.size)
            Path { path in
                path.addRect(rect)
            }
            .stroke(.white.opacity(0.8), lineWidth: 2)
        }
        .allowsHitTesting(false)
    }

    private func frameRect(in size: CGSize) -> CGRect {
        let containerAspect = size.width / max(size.height, 1)
        let width: CGFloat
        let height: CGFloat
        if containerAspect > aspectRatio {
            height = size.height
            width = height * aspectRatio
        } else {
            width = size.width
            height = width / aspectRatio
        }
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as? AVCaptureVideoPreviewLayer ?? AVCaptureVideoPreviewLayer()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        setVideoOrientation(.landscapeRight)
    }

    func setVideoOrientation(_ orientation: AVCaptureVideoOrientation) {
        guard let connection = videoPreviewLayer.connection, connection.isVideoOrientationSupported else { return }
        connection.videoOrientation = orientation
    }
}
