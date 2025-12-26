import SwiftUI
import AVFoundation
import MediaPlayer
import UIKit

struct ScoutCameraLayout: View {
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ScoutCameraViewModel
    @StateObject private var motionManager = MotionHeadingManager()
    @StateObject private var volumeObserver = VolumeButtonObserver()
    private let targetAspectRatio: CGFloat
    @State private var isCameraSelectionPresented = false
    @State private var isFrameLineSettingsPresented = false
    @State private var isLensPackPresented = false
    @State private var isCalibrationPresented = false
    @State private var lastCameraRole: String?
    @State private var lensToastMessage: String?
    @State private var showLensToast = false
    private let previewMargin: CGFloat = 40

    init(projectId: String, frameId: String, targetAspectRatio: CGFloat) {
        self.targetAspectRatio = targetAspectRatio
        _viewModel = StateObject(wrappedValue: ScoutCameraViewModel(projectId: projectId, frameId: frameId, targetAspectRatio: targetAspectRatio))
    }

    var body: some View {
        ZStack {
            Color(.cameraBackground).ignoresSafeArea()

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
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 0)
                }
                ZStack {
                    HStack {
                        VStack(spacing: 12) {
                            leftControlBar
                        }
                        Spacer()
                        VStack(spacing: 12) {
                            rightControlBar
                        }
                    }
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
        .sheet(isPresented: $isCameraSelectionPresented) {
            CameraSelectionSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $isFrameLineSettingsPresented) {
            CameraSettingsSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $isLensPackPresented) {
            LensPackSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $isCalibrationPresented) {
            FOVCalibrationView(scoutViewModel: viewModel)
        }
        .overlay(VolumeButtonSuppressor(volumeView: volumeObserver.volumeView))
    }

    private var rightControlBar: some View {
        VStack{
            Spacer()
            VStack(spacing: 6) {
                Button {
                    isFrameLineSettingsPresented = true
                } label: {
                    Image(systemName: "viewfinder.rectangular")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Button {
                    isCalibrationPresented = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            //.buttonStyle(.plain)
            Spacer()
        }
    }
    
    private var leftControlBar: some View {
        VStack {
            
        }
    }
    
    
    private var topInfoBar: some View {
        HStack {
            HStack(spacing: 6) {
                Button("Cancel") {
                    dismiss()
                }
                .foregroundStyle(.white)
                .font(.caption.weight(.semibold))
                Button {
                    isCameraSelectionPresented = true
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
            VStack(alignment: .trailing, spacing: 10) {
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
    }

    private var selectedCameraLabel: String {
        guard let camera = viewModel.selectedCamera else {
            return "None"
        }
        return "\(camera.brand) \(camera.model)"
    }

    private var selectedModeLabel: String {
        guard let mode = viewModel.selectedMode else {
            return "None"
        }
        return formattedModeLabel(camera: viewModel.selectedCamera, mode: mode)
    }

    private func formattedModeLabel(camera: DBCamera?, mode: DBCameraMode) -> String {
        var modeLabel = mode.name
        if let camera {
            let cameraFullName = "\(camera.brand) \(camera.model)"
            if modeLabel.hasPrefix("\(cameraFullName) ") {
                modeLabel = String(modeLabel.dropFirst(cameraFullName.count + 1))
            }
            let modelLabel = shortModelLabel(camera)
            if !modelLabel.isEmpty, !modeLabel.hasPrefix(modelLabel) {
                modeLabel = "\(modelLabel) \(modeLabel)"
            }
        }
        if let resolution = mode.resolution, !resolution.isEmpty {
            let formattedResolution = resolution.replacingOccurrences(of: "x", with: " x ")
            modeLabel += " (\(formattedResolution))"
        }
        return modeLabel
    }

    private func shortModelLabel(_ camera: DBCamera) -> String {
        let model = camera.model
        if camera.brand == "ARRI", model.hasPrefix("Alexa ") {
            return String(model.dropFirst("Alexa ".count))
        }
        return model
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

                    Section("Overlays") {
                        Toggle("Crosshair", isOn: $viewModel.showCrosshair)
                        Toggle("Grid", isOn: $viewModel.showGrid)
                        Toggle("Frame Shading", isOn: $viewModel.showFrameShading)
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

    private struct CameraSelectionSheet: View {
        @Environment(\.dismiss) private var dismiss
        @ObservedObject var viewModel: ScoutCameraViewModel

        var body: some View {
            NavigationStack {
                List {
                    Section {
                        NavigationLink {
                            ScoutCameraLayout.SelectionList(
                                items: viewModel.availableCameras,
                                selectedId: viewModel.selectedCamera?.id,
                                title: "Camera",
                                rowTitle: { "\($0.brand) \($0.model)" },
                                rowSubtitle: { cameraSensorLabel($0) }
                            ) { camera in
                                viewModel.selectedCamera = camera
                            }
                        } label: {
                            SettingsSectionLabel(title: "Camera", value: selectedCameraLabel)
                        }

                        NavigationLink {
                            ModeSelectionList(viewModel: viewModel)
                        } label: {
                            SettingsSectionLabel(title: "Mode", value: viewModel.selectedMode?.name ?? "None")
                        }
                    }
                }
                .navigationTitle("Camera Selection")
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

        private var selectedCameraLabel: String {
            guard let camera = viewModel.selectedCamera else {
                return "None"
            }
            return "\(camera.brand) \(camera.model)"
        }

        private func cameraSensorLabel(_ camera: DBCamera) -> String? {
            if let width = camera.sensorWidthMm, let height = camera.sensorHeightMm {
                return "\(String(format: "%.1f", width)) × \(String(format: "%.1f", height)) mm"
            }
            if let sensorType = camera.sensorType, !sensorType.isEmpty {
                return sensorType
            }
            return nil
        }

    }

    private struct ModeSelectionList: View {
        @Environment(\.dismiss) private var dismiss
        @ObservedObject var viewModel: ScoutCameraViewModel
        @State private var showAnamorphicOnly = false

        private var filteredModes: [DBCameraMode] {
            if showAnamorphicOnly {
                return viewModel.availableModes.filter { $0.anamorphicPreviewSqueeze != nil }
            }
            return viewModel.availableModes
        }

        var body: some View {
            List {
                Section {
                    Toggle("Anamorphic modes only", isOn: $showAnamorphicOnly)
                }

                Section {
                    ForEach(filteredModes) { mode in
                        Button {
                            viewModel.selectedMode = mode
                            dismiss()
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(modeDisplayName(mode))
                                    ModeMetadataChips(mode: mode)
                                }
                                Spacer()
                                if viewModel.selectedMode?.id == mode.id {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.semibold))
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Mode")
            .navigationBarTitleDisplayMode(.inline)
        }

        private func modeDisplayName(_ mode: DBCameraMode) -> String {
            guard let camera = viewModel.selectedCamera else {
                return mode.name
            }
            let cameraLabel = "\(camera.brand) \(camera.model)"
            guard mode.name.hasPrefix(cameraLabel) else {
                return mode.name
            }
            let trimmed = mode.name.dropFirst(cameraLabel.count).trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? mode.name : trimmed
        }
    }

    private struct ModeMetadataChips: View {
        let mode: DBCameraMode

        private var chips: [String] {
            var values: [String] = []
            if let captureGate = mode.captureGate, !captureGate.isEmpty {
                values.append(captureGate)
            }
            if let resolution = formattedResolutionLabel(mode.resolution) {
                values.append(resolution)
            }
            if let squeeze = mode.anamorphicPreviewSqueeze {
                values.append(formattedSqueezeLabel(squeeze))
            }
            if let delivery = mode.deliveryAspectRatio, !delivery.isEmpty {
                values.append(delivery)
            }
            return values
        }

        var body: some View {
            if chips.isEmpty {
                EmptyView()
            } else {
                HStack(spacing: 6) {
                    ForEach(chips, id: \.self) { chip in
                        Text(chip)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
        }

        private func formattedSqueezeLabel(_ squeeze: Double) -> String {
            if abs(squeeze.rounded() - squeeze) < 0.01 {
                return "\(Int(squeeze.rounded()))x"
            }
            return String(format: "%.1fx", squeeze)
        }

        private func formattedResolutionLabel(_ resolution: String?) -> String? {
            guard let resolution, !resolution.isEmpty else {
                return nil
            }
            return resolution.replacingOccurrences(of: "x", with: " x ")
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
            Button {
                viewModel.selectPreviousLens()
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 30, weight: .semibold))
            }
            .foregroundStyle(.white)
            Spacer()
            VStack(spacing: 4) {
                VStack() {
                    Text(lensInfoText)
                        .font(.system(size: 30, weight: .semibold))
                        .lineSpacing(1)
                    Text("mm")
                        .font(.system(size: 12, weight: .regular))
                        .lineSpacing(1)
                }
//                if let match = viewModel.matchResult {
//                    Text("\(match.cameraRole.uppercased()) • \(String(format: "%.2fx", match.zoomFactor))")
//                        .font(.caption2)
//                        .foregroundStyle(.white.opacity(0.7))
//                }
            }
            .foregroundStyle(.white)
            Spacer()
            
            HStack(spacing: 12) {
                Button {
                    viewModel.capturePhoto()
                } label: {
//                    Circle()
//                        .fill(Color.white)
//                        .frame(width: 72, height: 72)
//                        .overlay(
//                            Circle()
//                                .stroke(Color.black.opacity(0.6), lineWidth: 3)
//                        )
                    Image(systemName: "camera.circle.fill")
                        .font(.system(size: 30, weight: .regular))
                }
                Button {
                    viewModel.selectNextLens()
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 30, weight: .semibold))
                }
                .foregroundStyle(.white)
            }
        }
    }

    private var debugBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let info = viewModel.debugInfo {
                Text("HFOV Target \(String(format: "%.2f", info.targetHFOVDegrees))° • Achieved \(String(format: "%.2f", info.achievedHFOVDegrees))°")
                Text("Error \(String(format: "%.2f", info.errorDegrees))° • \(info.cameraRole.uppercased()) @ \(String(format: "%.3fx", info.zoomFactor))")
                Text("Focal \(String(format: "%.1f", info.focalLengthMm))mm")
                ForEach(info.candidates, id: \.cameraRole) { candidate in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(candidate.cameraRole.uppercased()) Native \(String(format: "%.2f", candidate.nativeHFOVDegrees))°")
                        Text("Required \(String(format: "%.3fx", candidate.requiredZoom)) • Clamped \(String(format: "%.3fx", candidate.clampedZoom)) (min \(String(format: "%.2fx", candidate.minZoom)), max \(String(format: "%.2fx", candidate.maxZoom)))")
                        Text("Achieved \(String(format: "%.2f", candidate.achievedHFOVDegrees))° • Error \(String(format: "%.2f", candidate.errorDegrees))°")
                    }
                }
            } else {
                Text("HFOV matching unavailable")
            }
        }
        .font(.caption2)
        .foregroundStyle(.white)
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

                if viewModel.showFrameShading,
                   let frameLineAspect = viewModel.selectedFrameLine.aspectRatio {
                    FrameShadingOverlay(aspectRatio: frameLineAspect)
                        .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height)
                }

                if viewModel.showGrid {
                    GridOverlay(aspectRatio: viewModel.selectedFrameLine.aspectRatio)
                        .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height)
                }

                if viewModel.showCrosshair {
                    CrosshairOverlay()
                        .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height)
                }
            }
        }
        .aspectRatio(viewModel.sensorAspectRatio ?? targetAspectRatio, contentMode: .fit)
    }

    private var lensInfoText: String {
        let focalText = "\(Int(viewModel.activeFocalLengthMm))"
//        if let targetHFOV = viewModel.debugInfo?.targetHFOVDegrees {
//            return "\(focalText) • \(Int(targetHFOV.rounded()))°"
//        }
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
        view.configurePreviewConnection(orientation: .landscapeRight)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let previewView = uiView as? PreviewView else { return }
        previewView.videoPreviewLayer.session = session
        previewView.configurePreviewConnection(orientation: .landscapeRight)
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

private struct FrameShadingOverlay: View {
    let aspectRatio: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let rect = frameRect(in: proxy.size)
            Path { path in
                path.addRect(CGRect(origin: .zero, size: proxy.size))
                path.addRect(rect)
            }
            .fill(.black.opacity(0.7), style: FillStyle(eoFill: true))
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

private struct GridOverlay: View {
    let aspectRatio: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            let rect = aspectRatio.map { frameRect(in: proxy.size, aspectRatio: $0) }
                ?? CGRect(origin: .zero, size: proxy.size)
            let oneThirdWidth = rect.width / 3
            let oneThirdHeight = rect.height / 3
            Path { path in
                path.move(to: CGPoint(x: rect.minX + oneThirdWidth, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.minX + oneThirdWidth, y: rect.maxY))
                path.move(to: CGPoint(x: rect.minX + oneThirdWidth * 2, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.minX + oneThirdWidth * 2, y: rect.maxY))

                path.move(to: CGPoint(x: rect.minX, y: rect.minY + oneThirdHeight))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + oneThirdHeight))
                path.move(to: CGPoint(x: rect.minX, y: rect.minY + oneThirdHeight * 2))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + oneThirdHeight * 2))
            }
            .stroke(.white.opacity(0.6), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    private func frameRect(in size: CGSize, aspectRatio: CGFloat) -> CGRect {
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

private struct CrosshairOverlay: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let centerX = width / 2
            let centerY = height / 2
            let length: CGFloat = min(width, height) * 0.08
            Path { path in
                path.move(to: CGPoint(x: centerX - length, y: centerY))
                path.addLine(to: CGPoint(x: centerX + length, y: centerY))
                path.move(to: CGPoint(x: centerX, y: centerY - length))
                path.addLine(to: CGPoint(x: centerX, y: centerY + length))
            }
            .stroke(.white.opacity(0.8), lineWidth: 1.5)
        }
        .allowsHitTesting(false)
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
        configurePreviewConnection(orientation: .landscapeRight)
    }

    func configurePreviewConnection(orientation: AVCaptureVideoOrientation) {
        guard let connection = videoPreviewLayer.connection, connection.isVideoOrientationSupported else { return }
        connection.videoOrientation = orientation
        if connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .off
        }
    }
}

private final class VolumeButtonObserver: ObservableObject {
    var onVolumeChange: (() -> Void)?
    private var observation: NSKeyValueObservation?
    private var lastVolume: Float = AVAudioSession.sharedInstance().outputVolume
    private var isRestoringVolume = false
    let volumeView: MPVolumeView = {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = false
        view.showsVolumeSlider = true
        view.alpha = 0.0001
        return view
    }()

    private var volumeSlider: UISlider? {
        volumeView.subviews.compactMap { $0 as? UISlider }.first
    }

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
            if self.isRestoringVolume {
                self.isRestoringVolume = false
                self.lastVolume = newVolume
                return
            }
            guard abs(newVolume - self.lastVolume) > 0.001 else { return }
            let previousVolume = self.lastVolume
            self.lastVolume = newVolume
            DispatchQueue.main.async {
                self.onVolumeChange?()
                self.isRestoringVolume = true
                self.volumeSlider?.value = previousVolume
                self.lastVolume = previousVolume
            }
        }
    }

    func stop() {
        observation?.invalidate()
        observation = nil
    }
}

private struct VolumeButtonSuppressor: UIViewRepresentable {
    let volumeView: MPVolumeView

    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: .zero)
        volumeView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(volumeView)
        NSLayoutConstraint.activate([
            volumeView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            volumeView.topAnchor.constraint(equalTo: container.topAnchor),
            volumeView.widthAnchor.constraint(equalToConstant: 1),
            volumeView.heightAnchor.constraint(equalToConstant: 1)
        ])
        container.isUserInteractionEnabled = false
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
