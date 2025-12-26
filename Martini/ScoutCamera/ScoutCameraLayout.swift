import SwiftUI
import AVFoundation
import UIKit

struct ScoutCameraLayout: View {
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ScoutCameraViewModel
    @StateObject private var motionManager = MotionHeadingManager()
    @StateObject private var volumeObserver = VolumeButtonObserver()
    private let targetAspectRatio: CGFloat
    @State private var isCameraSettingsPresented = false
    @State private var isLensPackPresented = false
    @State private var lastCameraRole: String?
    @State private var lensToastMessage: String?
    @State private var showLensToast = false
    private let previewMargin: CGFloat = 80

    init(projectId: String, frameId: String, targetAspectRatio: CGFloat) {
        self.targetAspectRatio = targetAspectRatio
        _viewModel = StateObject(wrappedValue: ScoutCameraViewModel(projectId: projectId, frameId: frameId, targetAspectRatio: targetAspectRatio))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { proxy in
                let previewWidth = max(proxy.size.width - previewMargin * 2, 0)
                let previewHeight = max(proxy.size.height - previewMargin * 2, 0)
                ZStack {
                    previewPanel
                        .frame(width: previewWidth, height: previewHeight)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        .gesture(lensSwipeGesture)

                    VStack(spacing: 12) {
                        topInfoBar
                        if AppConfig.debugMode {
                            debugBar
                        }
                        Spacer()
                        bottomControlBar
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }

            if viewModel.isCapturing {
                captureOverlay
            }

            if showLensToast, let lensToastMessage {
                lensToast(message: lensToastMessage)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showLensToast)
        .onAppear {
            AppDelegate.orientationLock = .landscape
            UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
            motionManager.start()
            volumeObserver.onVolumeChange = { viewModel.capturePhoto() }
            volumeObserver.start()
        }
        .onDisappear {
            motionManager.stop()
            AppDelegate.orientationLock = .all
            UIViewController.attemptRotationToDeviceOrientation()
            volumeObserver.stop()
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
        .onChange(of: viewModel.matchResult?.cameraRole) { newRole in
            handleCameraRoleChange(newRole)
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
        .sheet(isPresented: $isCameraSettingsPresented) {
            CameraSettingsSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $isLensPackPresented) {
            LensPackSheet(viewModel: viewModel)
        }
    }

    private var topInfoBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Button("Cancel") {
                    dismiss()
                }
                .foregroundStyle(.white)
                .font(.caption.weight(.semibold))
                Button {
                    isCameraSettingsPresented = true
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedCameraLabel)
                        Text(selectedModeLabel)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .font(.caption)
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            VStack(spacing: 4) {
                Text("\(motionManager.headingText) \(Int(motionManager.headingDegrees))°")
                Text("Tilt \(Int(motionManager.tiltDegrees))°")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            Spacer()
            Button {
                isLensPackPresented = true
            } label: {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Lens Pack")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(selectedLensPackLabel)
                        .font(.caption)
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
        }
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

    private var selectedLensPackLabel: String {
        viewModel.selectedLensPack?.displayName ?? "Select Pack"
    }

    private struct SelectionList<Item: Identifiable>: View {
        @Environment(\.dismiss) private var dismiss
        let items: [Item]
        let selectedId: Item.ID?
        let title: String
        let rowTitle: (Item) -> String
        let rowSubtitle: ((Item) -> String?)?
        let onSelect: (Item) -> Void

        var body: some View {
            List(items) { item in
                Button {
                    onSelect(item)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rowTitle(item))
                            if let subtitle = rowSubtitle?(item) {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                        Spacer()
                        if selectedId == item.id {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.insetGrouped)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private struct SettingsSectionLabel: View {
        let title: String
        let value: String

        var body: some View {
            HStack {
                Text(title)
                Spacer()
                Text(value)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private struct CameraSettingsSheet: View {
        @Environment(\.dismiss) private var dismiss
        @ObservedObject var viewModel: ScoutCameraViewModel

        var body: some View {
            NavigationStack {
                List {
                    Section {
                        NavigationLink {
                            ScoutCameraLayout.SelectionList(
                                items: FrameLineOption.allCases,
                                selectedId: viewModel.selectedFrameLine.id,
                                title: "Frame Lines",
                                rowTitle: { $0.rawValue },
                                rowSubtitle: { _ in nil }
                            ) { option in
                                viewModel.selectedFrameLine = option
                            }
                        } label: {
                            SettingsSectionLabel(title: "Frame Lines", value: viewModel.selectedFrameLine.rawValue)
                        }
                    }
                }
                .navigationTitle("Camera Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private struct LensPackSheet: View {
        @Environment(\.dismiss) private var dismiss
        @ObservedObject var viewModel: ScoutCameraViewModel

        var body: some View {
            NavigationStack {
                List {
                    if viewModel.availableLensPacks.isEmpty {
                        Text("No lens packs available.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.availableLensPacks) { pack in
                            Button {
                                viewModel.selectLensPack(pack)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(pack.displayName)
                                        Text("\(pack.lenses.count) lenses")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if viewModel.selectedLensPack?.id == pack.id {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .navigationTitle("Lens Packs")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private var bottomControlBar: some View {
        HStack {
            Spacer()
            Button {
                viewModel.selectPreviousLens()
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 24, weight: .semibold))
            }
            .foregroundStyle(.white)
            Spacer()
            VStack(spacing: 4) {
                Text(lensInfoText)
                    .font(.headline.weight(.semibold))
                if let match = viewModel.matchResult {
                    Text("\(match.cameraRole.uppercased()) • \(String(format: "%.2fx", match.zoomFactor))")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .foregroundStyle(.white)
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
            Button {
                viewModel.selectNextLens()
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 24, weight: .semibold))
            }
            .foregroundStyle(.white)
            Spacer()
        }
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

    private var lensInfoText: String {
        let focalText = "\(Int(viewModel.activeFocalLengthMm))mm"
        if let targetHFOV = viewModel.debugInfo?.targetHFOVDegrees {
            return "\(focalText) • \(Int(targetHFOV.rounded()))°"
        }
        return focalText
    }

    private var lensSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                let vertical = value.translation.height
                let horizontal = value.translation.width
                guard abs(vertical) > abs(horizontal), abs(vertical) > 30 else { return }
                if vertical < 0 {
                    viewModel.selectNextLens()
                } else {
                    viewModel.selectPreviousLens()
                }
            }
    }

    private var captureOverlay: some View {
        ZStack {
            if let image = viewModel.capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            }
            Color.black.opacity(viewModel.capturedImage == nil ? 0.85 : 0.6)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                Text("Rendering photo…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(true)
    }

    private func handleCameraRoleChange(_ newRole: String?) {
        guard let newRole else { return }
        defer { lastCameraRole = newRole }
        guard let previousRole = lastCameraRole, previousRole != newRole else { return }
        let label = lensRoleLabel(for: newRole)
        lensToastMessage = "Switched to \(label) lens"
        withAnimation {
            showLensToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation {
                showLensToast = false
            }
        }
    }

    private func lensRoleLabel(for role: String) -> String {
        switch role {
        case "ultra":
            return "Ultra Wide"
        case "tele":
            return "Telephoto"
        case "main":
            return "Wide"
        default:
            return role.capitalized
        }
    }

    private func lensToast(message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.7))
                .clipShape(Capsule())
                .padding(.bottom, 112)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
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

private final class VolumeButtonObserver: ObservableObject {
    var onVolumeChange: (() -> Void)?
    private var observation: NSKeyValueObservation?
    private var lastVolume: Float = AVAudioSession.sharedInstance().outputVolume

    func start() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            return
        }
        lastVolume = session.outputVolume
        observation = session.observe(\.outputVolume, options: [.new]) { [weak self] session, change in
            guard let self else { return }
            let newVolume = change.newValue ?? session.outputVolume
            guard abs(newVolume - self.lastVolume) > 0.001 else { return }
            self.lastVolume = newVolume
            DispatchQueue.main.async {
                self.onVolumeChange?()
            }
        }
    }

    func stop() {
        observation?.invalidate()
        observation = nil
    }
}
