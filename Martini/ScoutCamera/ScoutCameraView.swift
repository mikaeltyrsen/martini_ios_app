import SwiftUI
import AVFoundation
import UIKit

struct ScoutCameraView: View {
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ScoutCameraViewModel
    @StateObject private var motionManager = MotionHeadingManager()
    private let targetAspectRatio: CGFloat
    @State private var isSettingsOpen = false
    @State private var expandedSections: Set<SettingsSection> = [.camera]

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
                if AppConfig.debugMode {
                    debugBar
                }
                previewPanel
                captureBar
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)

            if isSettingsOpen {
                settingsDrawer
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSettingsOpen)
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
            Button {
                isSettingsOpen.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.leading, 12)
        }
        .padding(.horizontal)
    }

    private var settingsDrawer: some View {
        GeometryReader { proxy in
            ZStack(alignment: .trailing) {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture {
                        isSettingsOpen = false
                    }

                settingsPanel
                    .frame(width: min(360, proxy.size.width * 0.6))
                    .transition(.move(edge: .trailing))
            }
        }
    }

    private var settingsPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Camera Settings")
                    .font(.headline)
                Spacer()
                Button {
                    isSettingsOpen = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                }
            }
            .padding(16)
            .foregroundStyle(.white)

            List {
                Section {
                    DisclosureGroup(isExpanded: expandedBinding(for: .camera)) {
                        ForEach(viewModel.availableCameras, id: \.id) { camera in
                            selectionRow(
                                title: "\(camera.brand) \(camera.model)",
                                isSelected: viewModel.selectedCamera?.id == camera.id
                            ) {
                                viewModel.selectedCamera = camera
                            }
                        }
                    } label: {
                        settingsSectionLabel(title: "Camera", value: selectedCameraLabel)
                    }
                }

                Section {
                    DisclosureGroup(isExpanded: expandedBinding(for: .mode)) {
                        ForEach(viewModel.availableModes, id: \.id) { mode in
                            selectionRow(
                                title: mode.name,
                                isSelected: viewModel.selectedMode?.id == mode.id
                            ) {
                                viewModel.selectedMode = mode
                            }
                        }
                    } label: {
                        settingsSectionLabel(title: "Mode", value: selectedModeLabel)
                    }
                }

                Section {
                    DisclosureGroup(isExpanded: expandedBinding(for: .lens)) {
                        ForEach(viewModel.availableLenses, id: \.id) { lens in
                            selectionRow(
                                title: "\(lens.brand) \(lens.series)",
                                isSelected: viewModel.selectedLens?.id == lens.id
                            ) {
                                viewModel.selectedLens = lens
                            }
                        }
                    } label: {
                        settingsSectionLabel(title: "Lens", value: selectedLensLabel)
                    }
                }

                Section {
                    DisclosureGroup(isExpanded: expandedBinding(for: .frameLines)) {
                        ForEach(FrameLineOption.allCases) { option in
                            selectionRow(
                                title: option.rawValue,
                                isSelected: viewModel.selectedFrameLine == option
                            ) {
                                viewModel.selectedFrameLine = option
                            }
                        }
                    } label: {
                        settingsSectionLabel(title: "Frame Lines", value: viewModel.selectedFrameLine.rawValue)
                    }
                }

                if let lens = viewModel.selectedLens, lens.isZoom,
                   let minFocal = lens.focalLengthMinMm, let maxFocal = lens.focalLengthMaxMm {
                    Section("Focal Length") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(Int(viewModel.focalLengthMm))mm")
                                .font(.headline)
                            Slider(value: $viewModel.focalLengthMm, in: minFocal...maxFocal, step: 1)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.black.opacity(0.6))
            .foregroundStyle(.white)
        }
        .background(Color.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.trailing, 16)
        .padding(.vertical, 16)
    }

    private var selectedCameraLabel: String {
        guard let camera = viewModel.selectedCamera else {
            return "None"
        }
        return "\(camera.brand) \(camera.model)"
    }

    private var selectedModeLabel: String {
        viewModel.selectedMode?.name ?? "None"
    }

    private var selectedLensLabel: String {
        guard let lens = viewModel.selectedLens else {
            return "None"
        }
        return "\(lens.brand) \(lens.series)"
    }

    private func settingsSectionLabel(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private func selectionRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func expandedBinding(for section: SettingsSection) -> Binding<Bool> {
        Binding(
            get: { expandedSections.contains(section) },
            set: { isExpanded in
                if isExpanded {
                    expandedSections.insert(section)
                } else {
                    expandedSections.remove(section)
                }
            }
        )
    }

    private enum SettingsSection: Hashable {
        case camera
        case mode
        case lens
        case frameLines
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

    private var debugBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let info = viewModel.debugInfo {
                Text("HFOV Target \(String(format: "%.1f", info.targetHFOVDegrees))° • Achieved \(String(format: "%.1f", info.achievedHFOVDegrees))°")
                Text("Error \(String(format: "%.2f", info.errorDegrees))° • \(info.cameraRole.uppercased()) @ \(String(format: "%.2fx", info.zoomFactor))")
                Text("Focal \(String(format: "%.1f", info.focalLengthMm))mm")
            } else {
                Text("HFOV matching unavailable")
            }
        }
        .font(.caption2)
        .foregroundStyle(.white)
        .padding(.horizontal)
    }

    private var previewPanel: some View {
        GeometryReader { proxy in
            let previewAspectRatio = viewModel.sensorAspectRatio ?? targetAspectRatio
            ZStack {
                CameraPreviewView(session: viewModel.captureManager.session)
                    .aspectRatio(previewAspectRatio, contentMode: .fit)
                    .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)

                if let frameLineAspect = viewModel.selectedFrameLine.aspectRatio {
                    FrameLineOverlay(aspectRatio: frameLineAspect)
                        .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height)
                }
            }
        }
        .aspectRatio(viewModel.sensorAspectRatio ?? targetAspectRatio, contentMode: .fit)
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
