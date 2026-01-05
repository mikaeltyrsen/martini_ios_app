import SwiftUI
import AVFoundation
import MediaPlayer
import UIKit

struct ScoutCameraLayout: View {
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: ScoutCameraViewModel
    @ObservedObject private var calibrationStore: FOVCalibrationStore
    @StateObject private var motionManager = MotionHeadingManager()
    @StateObject private var volumeObserver = VolumeButtonObserver()
    private let frameId: String
    private let targetAspectRatio: CGFloat
    @State private var isCameraSelectionPresented = false
    @State private var isFrameLineSettingsPresented = false
    @State private var isLensPackPresented = false
    @State private var isCalibrationPresented = false
    @State private var lastCameraRole: String?
    @State private var lensToastMessage: String?
    @State private var showLensToast = false
    @State private var previewOrientation: AVCaptureVideoOrientation = .landscapeRight
    @AppStorage("scoutCameraShowReferenceOverlay") private var showReferenceOverlay = false
    @AppStorage("scoutCameraShowBoardGuide") private var showBoardGuide = false
    @AppStorage("scoutCameraDebugMode") private var debugMode = true
    @State private var previewLayer: AVCaptureVideoPreviewLayer?
    @State private var capturedPhoto: CapturedPhoto?
    private let previewMargin: CGFloat = 40
    private let referenceOverlayPadding = EdgeInsets(top: 0, leading: 0, bottom: 120, trailing: 72)

    init(projectId: String, frameId: String, targetAspectRatio: CGFloat, creativeId: String? = nil) {
        self.frameId = frameId
        self.targetAspectRatio = targetAspectRatio
        let viewModel = ScoutCameraViewModel(
            projectId: projectId,
            frameId: frameId,
            creativeId: creativeId,
            targetAspectRatio: targetAspectRatio
        )
        _viewModel = StateObject(wrappedValue: viewModel)
        _calibrationStore = ObservedObject(wrappedValue: viewModel.calibrationStore)
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
                        if debugMode {
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

                if showReferenceOverlay, let selection = referenceImageSelection {
                    referenceImageOverlay(selection: selection, in: proxy.size)
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
            previewOrientation = currentPreviewOrientation()
            viewModel.captureManager.updateVideoOrientation(previewOrientation)
            if viewModel.creativeId == nil {
                let creativeId = authService.frames.first(where: { $0.id == frameId })?.creativeId
                viewModel.updateCreativeId(creativeId)
            }
            motionManager.start()
            volumeObserver.onVolumeChange = { viewModel.capturePhoto() }
            volumeObserver.start()
        }
        .onDisappear {
            motionManager.stop()
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
        .onChange(of: viewModel.processedImage) { newValue in
            capturedPhoto = newValue.map { CapturedPhoto(image: $0) }
        }
        .onChange(of: previewOrientation) { newValue in
            viewModel.captureManager.updateVideoOrientation(newValue)
            if viewModel.captureManager.isRunning {
                viewModel.captureManager.restartSessionForOrientationChange()
            } else {
                Task { await viewModel.updateCaptureConfiguration() }
            }
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                Task { await viewModel.updateCaptureConfiguration() }
            case .background:
                viewModel.captureManager.stop()
            default:
                break
            }
        }
        .onChange(of: showReferenceOverlay) { newValue in
            if !newValue {
                showBoardGuide = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            let nextOrientation = currentPreviewOrientation()
            if nextOrientation != previewOrientation {
                previewOrientation = nextOrientation
            }
        }
        .alert("Scout Camera Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
        .fullScreenCover(item: $capturedPhoto) { photo in
            ScoutCameraReviewView(
                image: photo.image,
                onImport: { await handleImport() },
                onPrepareShare: { await viewModel.prepareShareImage() },
                onRetake: {
                    capturedPhoto = nil
                    viewModel.capturedImage = nil
                    viewModel.processedImage = nil
                },
                onCancel: {
                    capturedPhoto = nil
                    viewModel.capturedImage = nil
                    viewModel.processedImage = nil
                    dismiss()
                }
            )
        }
        .sheet(isPresented: $isCameraSelectionPresented) {
            CameraSelectionSheet(viewModel: viewModel)
        }
        .onChange(of: isCameraSelectionPresented) { newValue in
            if !newValue {
                resumePreviewIfNeeded()
            }
        }
        .sheet(isPresented: $isFrameLineSettingsPresented) {
            CameraSettingsSheet(viewModel: viewModel)
        }
        .onChange(of: isFrameLineSettingsPresented) { newValue in
            if !newValue {
                resumePreviewIfNeeded()
            }
        }
        .sheet(isPresented: $isLensPackPresented) {
            LensPackSheet(viewModel: viewModel)
        }
        .onChange(of: isLensPackPresented) { newValue in
            if !newValue {
                resumePreviewIfNeeded()
            }
        }
        .sheet(isPresented: $isCalibrationPresented) {
            FOVCalibrationView(scoutViewModel: viewModel)
        }
        .onChange(of: isCalibrationPresented) { newValue in
            if !newValue {
                resumePreviewIfNeeded()
            }
        }
        .overlay(VolumeButtonSuppressor(volumeView: volumeObserver.volumeView))
    }

    private var rightControlBar: some View {
        VStack{
            Spacer()
            VStack(spacing: 25) {
                Button {
                    isFrameLineSettingsPresented = true
                } label: {
                    Image(systemName: "viewfinder.rectangular")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(isFramingActive ? .white : .gray)
                }

                Button {
                    isCalibrationPresented = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(isCalibrationActive ? .white.opacity(0.7) : .gray)
                }
                .buttonStyle(.plain)

                Button {
                    let nextValue = !showReferenceOverlay
                    showReferenceOverlay = nextValue
                    if !nextValue {
                        showBoardGuide = false
                    }
                } label: {
                    Image(systemName: showReferenceOverlay ? "photo.fill" : "photo")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(showReferenceOverlay ? .white.opacity(0.7) : .gray)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reference Image")
                .accessibilityValue(showReferenceOverlay ? "On" : "Off")
                .disabled(referenceImageSelection == nil)

                Button {
                    debugMode.toggle()
                } label: {
                    Image(systemName: debugMode ? "ladybug.fill" : "ladybug")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(debugMode ? .white.opacity(0.7) : .gray)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Debug Overlay")
                .accessibilityValue(debugMode ? "On" : "Off")
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
        ZStack {
            HStack {
                HStack(spacing: 6) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.white.opacity(0.2)))
                    }
                    .buttonStyle(.plain)
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
            VStack(spacing: 4) {
                Text("\(motionManager.headingText) \(Int(motionManager.headingDegrees))°")
                Text("Tilt \(Int(motionManager.tiltDegrees))°")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
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

    private var isFramingActive: Bool {
        !viewModel.frameLineConfigurations.isEmpty
            || viewModel.showCrosshair
            || viewModel.showGrid
            || viewModel.showFrameShading
    }

    private var isCalibrationActive: Bool {
        !calibrationStore.multipliers.values.allSatisfy { abs($0 - 1.0) < 0.0001 }
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
                    Section("Frame Lines") {
                        NavigationLink {
                            FrameLineAddList(viewModel: viewModel)
                        } label: {
                            Label("Add Frame Line", systemImage: "plus")
                        }
                    }

                    Section("Selected Frame Lines") {
                        if viewModel.frameLineConfigurations.isEmpty {
                            Text("No frame lines selected.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(viewModel.frameLineConfigurations) { configuration in
                                NavigationLink {
                                    FrameLineDetailView(configuration: viewModel.binding(for: configuration))
                                } label: {
                                    FrameLineRow(configuration: configuration)
                                }
                            }
                            .onDelete { indexSet in
                                for index in indexSet {
                                    let configuration = viewModel.frameLineConfigurations[index]
                                    viewModel.removeFrameLineConfiguration(configuration)
                                }
                            }
                            .onMove(perform: viewModel.moveFrameLineConfigurations)
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
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private struct FrameLineRow: View {
        let configuration: FrameLineConfiguration

        var body: some View {
            HStack {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(configuration.option.rawValue)
                    Text(configurationSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: configuration.design.symbolName)
                    .foregroundStyle(configuration.color.swiftUIColor.opacity(configuration.opacity))
            }
        }

        private var configurationSummary: String {
            "\(configuration.color.displayName) • \(Int(configuration.opacity * 100))% • \(configuration.design.displayName) • \(Int(configuration.thickness)) pt"
        }
    }

    private struct FrameLineAddList: View {
        @Environment(\.dismiss) private var dismiss
        @ObservedObject var viewModel: ScoutCameraViewModel

        var body: some View {
            List {
                Section("Choose a Frame Line") {
                    ForEach(FrameLineOption.allCases.filter { $0 != .none }) { option in
                        Button {
                            viewModel.addFrameLineOption(option)
                            dismiss()
                        } label: {
                            HStack {
                                Text(option.rawValue)
                                Spacer()
                                if viewModel.isFrameLineSelected(option) {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.semibold))
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isFrameLineSelected(option))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Add Frame Line")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private struct FrameLineDetailView: View {
        @Binding var configuration: FrameLineConfiguration

        var body: some View {
            Form {
                Section("Color") {
                    Picker("Color", selection: $configuration.color) {
                        ForEach(FrameLineColor.selectableColors(including: configuration.color)) { color in
                            HStack(spacing: 12) {
                                Image(systemName: "circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(color.swiftUIColor)
                                Text(color.displayName)
                            }
                            .tag(color)
                        }
                    }
                    
//                    HStack() {
//                        Text("Color")
//                        Menu {
//                            ForEach(FrameLineColor.allCases) { color in
//                                Button {
//                                    configuration.color = color
//                                } label: {
//                                    HStack(spacing: 12) {
//                                        Image(systemName: "circle.fill")
//                                            .foregroundStyle(color.swiftUIColor)
//                                        Text(color.displayName)
//                                    }
//                                }
//                            }
//                        } label: {
//                            HStack(spacing: 12) {
//                                Spacer()
//                                Image(systemName: "circle.fill")
//                                    .foregroundStyle(configuration.color.swiftUIColor)
//                                Text(configuration.color.displayName)
//                                    .foregroundStyle(.primary)
//                            }
//                        }
//                    }
                    
                }

                Section("Opacity") {
                    VStack(alignment: .leading, spacing: 8) {
                        Slider(value: $configuration.opacity, in: 0...1, step: 0.01)
                        Text("\(Int(configuration.opacity * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Line Design") {
                    Picker("Line Design", selection: $configuration.design) {
                        ForEach(FrameLineDesign.allCases) { design in
                            HStack(spacing: 12) {
                                Image(systemName: design.symbolName)
                                Text(design.displayName)
                            }
                                .tag(design)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Thickness")
                        Slider(value: $configuration.thickness, in: 1...4, step: 1)
                        Text("\(Int(configuration.thickness)) pt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(configuration.option.rawValue)
            .navigationBarTitleDisplayMode(.inline)
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
        ZStack {
            HStack {
                Button {
                    viewModel.selectPreviousLens()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 30, weight: .semibold))
                }
                .foregroundStyle(.white)
                Spacer()

                HStack(spacing: 12) {
                    Button {
                        viewModel.capturePhoto()
                    } label: {
                        Image(systemName: "camera.circle.fill")
                            .font(.system(size: 30, weight: .regular))
                    }
                    Button {
                        viewModel.selectNextLens()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 30, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                }
            }
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
            let previewRect = previewBounds(in: proxy.size, aspectRatio: previewAspectRatio)
            ZStack {
                CameraPreviewView(
                    session: viewModel.captureManager.session,
                    orientation: previewOrientation,
                    onPreviewLayerReady: { layer in
                        if previewLayer !== layer {
                            previewLayer = layer
                        }
                    }
                )
                    .aspectRatio(previewAspectRatio, contentMode: .fit)
                    .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)

                if showReferenceOverlay,
                   showBoardGuide,
                   let selection = referenceImageSelection {
                    ReferenceImageGuide(
                        url: selection.url,
                        crop: selection.crop,
                        aspectRatio: viewModel.primaryFrameLineOption.aspectRatio ?? targetAspectRatio
                    )
                        .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height)
                        .allowsHitTesting(false)
                }

                if viewModel.showFrameShading,
                   !viewModel.frameLineConfigurations.isEmpty {
                    FrameShadingOverlay(configurations: viewModel.frameLineConfigurations)
                        .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height)
                }

                if !viewModel.frameLineConfigurations.isEmpty {
                    FrameLineOverlay(configurations: viewModel.frameLineConfigurations)
                        .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height)
                }

                if viewModel.showGrid {
                    GridOverlay(aspectRatio: viewModel.primaryFrameLineOption.aspectRatio)
                        .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height)
                }

                if viewModel.showCrosshair {
                    CrosshairOverlay()
                        .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height)
                }

                if isPortraitOrientation {
                    portraitOverlay
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let threshold: CGFloat = 12
                        guard abs(value.translation.width) < threshold,
                              abs(value.translation.height) < threshold else { return }
                        handleTapToFocus(at: value.location, in: previewRect)
                    }
            )
        }
        .aspectRatio(viewModel.sensorAspectRatio ?? targetAspectRatio, contentMode: .fit)
    }

    private func previewBounds(in size: CGSize, aspectRatio: CGFloat) -> CGRect {
        let containerAspect = size.width / max(size.height, 1)
        let width: CGFloat
        let height: CGFloat
        if containerAspect > aspectRatio {
            height = size.height
            width = height * aspectRatio
        } else {
            width = size.width
            height = width / max(aspectRatio, 0.01)
        }
        let origin = CGPoint(x: (size.width - width) / 2, y: (size.height - height) / 2)
        return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }

    private func handleTapToFocus(at location: CGPoint, in previewRect: CGRect) {
        guard previewRect.contains(location) else { return }
        let localPoint = CGPoint(x: location.x - previewRect.minX, y: location.y - previewRect.minY)
        if let previewLayer {
            let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: localPoint)
            viewModel.captureManager.focus(at: devicePoint)
        } else {
            let normalized = CGPoint(x: localPoint.x / max(previewRect.width, 1),
                                     y: localPoint.y / max(previewRect.height, 1))
            viewModel.captureManager.focus(at: normalized)
        }
    }

    private var isPortraitOrientation: Bool {
        switch previewOrientation {
        case .portrait, .portraitUpsideDown:
            return true
        default:
            return false
        }
    }

    private var portraitOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
            VStack(spacing: 12) {
                Image(systemName: "rectangle.portrait.rotate")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Please rotate your phone")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Scout Camera works best in landscape.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .allowsHitTesting(true)
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
            if let image = viewModel.processedImage ?? viewModel.capturedImage {
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

    private var referenceImageSelection: ReferenceImageSelection? {
        guard let frame = authService.frames.first(where: { $0.id == frameId }) else {
            return nil
        }
        if let pinnedBoard = frame.boards?.first(where: { $0.isPinned }) {
            let pinnedURLString: String?
            if isVideoBoard(pinnedBoard) {
                pinnedURLString = pinnedBoard.fileThumbUrl ?? pinnedBoard.fileUrl
            } else {
                pinnedURLString = pinnedBoard.fileUrl ?? pinnedBoard.fileThumbUrl
            }
            if let pinnedURLString,
               let pinnedURL = URL(string: pinnedURLString) {
                return ReferenceImageSelection(url: pinnedURL, crop: pinnedBoard.fileCrop)
            }
        }
        if let fallbackURL = frame.availableAssets.first(where: { !$0.isVideo })?.url {
            return ReferenceImageSelection(url: fallbackURL, crop: frame.photoboardCrop ?? frame.crop)
        }
        return nil
    }

    private func isVideoBoard(_ board: FrameBoard) -> Bool {
        if let fileType = board.fileType?.lowercased(), fileType.contains("video") {
            return true
        }
        guard let urlString = board.fileUrl ?? board.fileThumbUrl,
              let url = URL(string: urlString) else {
            return false
        }
        let extensionValue = url.pathExtension.lowercased()
        return ["mp4", "mov", "m4v", "webm", "mkv", "m3u8"].contains(extensionValue)
    }

    private func referenceImageOverlay(selection: ReferenceImageSelection, in size: CGSize) -> some View {
        let maxLength = min(size.width, size.height) * 0.28
        return VStack {
            Spacer()
            HStack {
                Spacer()
                ReferenceImagePreview(
                    url: selection.url,
                    crop: selection.crop,
                    maxLength: maxLength,
                    aspectRatio: viewModel.primaryFrameLineOption.aspectRatio ?? targetAspectRatio
                )
                    .overlay {
                        Rectangle()
                            .stroke(Color.gray.opacity(0.8), lineWidth: 1)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: showBoardGuide
                            ? "arrow.down.right.and.arrow.up.left"
                            : "arrow.up.left.and.arrow.down.right"
                        )
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.black))
                        .padding(6)
                    }
                    .onTapGesture {
                        showBoardGuide.toggle()
                    }
                    .accessibilityLabel("Board Guide")
                    .accessibilityValue(showBoardGuide ? "On" : "Off")
            }
        }
        .padding(referenceOverlayPadding)
    }

    private struct ReferenceImageSelection {
        let url: URL
        let crop: String?
    }

    private struct CapturedPhoto: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    private struct ReferenceImagePreview: View {
        let url: URL
        let crop: String?
        let maxLength: CGFloat
        let aspectRatio: CGFloat?

        @State private var displayImage: UIImage?
        @State private var imageAspectRatio: CGFloat = 1

        var body: some View {
            Group {
                if let displayImage {
                    Image(uiImage: displayImage)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
            }
            .frame(width: previewSize.width, height: previewSize.height)
            .task(id: taskIdentifier) {
                await loadImage()
            }
        }

        private var previewSize: CGSize {
            let ratio = max(aspectRatio ?? imageAspectRatio, 0.01)
            if ratio >= 1 {
                return CGSize(width: maxLength, height: maxLength / ratio)
            }
            return CGSize(width: maxLength * ratio, height: maxLength)
        }

        private var taskIdentifier: String {
            "\(url.absoluteString)-\(crop ?? "")"
        }

        private func loadImage() async {
            guard let image = await ReferenceImageLoader.loadImage(url: url, crop: crop) else { return }
            let cropped = image
            await MainActor.run {
                displayImage = cropped
                imageAspectRatio = cropped.size.width / max(cropped.size.height, 1)
            }
        }
    }

    private struct ReferenceImageCrop {
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat

        func rect(in size: CGSize) -> CGRect {
            let imageWidth = max(size.width, 1)
            let imageHeight = max(size.height, 1)

            var cropX = x
            var cropY = y
            var cropWidth = width
            var cropHeight = height

            if cropWidth <= 1, cropHeight <= 1 {
                cropX *= imageWidth
                cropY *= imageHeight
                cropWidth *= imageWidth
                cropHeight *= imageHeight
            } else if cropWidth <= 100, cropHeight <= 100 {
                cropX = cropX / 100 * imageWidth
                cropY = cropY / 100 * imageHeight
                cropWidth = cropWidth / 100 * imageWidth
                cropHeight = cropHeight / 100 * imageHeight
            }

            cropWidth = max(1, min(cropWidth, imageWidth))
            cropHeight = max(1, min(cropHeight, imageHeight))
            cropX = max(0, min(cropX, imageWidth - cropWidth))
            cropY = max(0, min(cropY, imageHeight - cropHeight))

            return CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
        }
    }

    private struct ReferenceImageGuide: View {
        let url: URL
        let crop: String?
        let aspectRatio: CGFloat?

        @State private var displayImage: UIImage?
        @State private var imageAspectRatio: CGFloat = 1

        var body: some View {
            GeometryReader { proxy in
                let ratio = max(aspectRatio ?? imageAspectRatio, 0.01)
                let rect = frameRect(in: proxy.size, aspectRatio: ratio)
                ZStack {
                    if let displayImage {
                        Image(uiImage: displayImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: rect.width, height: rect.height)
                            .clipped()
                            .opacity(0.5)
                            .position(x: rect.midX, y: rect.midY)
                    } else {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    }
                }
            }
            .task(id: taskIdentifier) {
                await loadImage()
            }
            .allowsHitTesting(false)
        }

        private var taskIdentifier: String {
            "\(url.absoluteString)-\(crop ?? "")"
        }

        private func loadImage() async {
            guard let image = await ReferenceImageLoader.loadImage(url: url, crop: crop) else { return }
            await MainActor.run {
                displayImage = image
                imageAspectRatio = image.size.width / max(image.size.height, 1)
            }
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
            return CGRect(
                x: (size.width - width) / 2,
                y: (size.height - height) / 2,
                width: width,
                height: height
            )
        }
    }

    private enum ReferenceImageLoader {
        static func loadImage(url: URL, crop: String?) async -> UIImage? {
            guard let image = await ImageCache.shared.image(for: url) else { return nil }
            return cropImage(image, using: parseCrop(crop)) ?? image
        }

        private static func cropImage(_ image: UIImage, using crop: ReferenceImageCrop?) -> UIImage? {
            guard let crop, let cgImage = image.cgImage else { return nil }
            let imageWidth = CGFloat(cgImage.width)
            let imageHeight = CGFloat(cgImage.height)

            var rect = crop.rect(in: CGSize(width: imageWidth, height: imageHeight))
            rect = rect.intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
            guard rect.width > 1, rect.height > 1 else { return nil }

            guard let cropped = cgImage.cropping(to: rect.integral) else { return nil }
            return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
        }

        private static func parseCrop(_ value: String?) -> ReferenceImageCrop? {
            guard let value, !value.isEmpty else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            if let data = trimmed.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) {
                if let dict = json as? [String: Any] {
                    let x = number(from: dict["x"])
                        ?? number(from: dict["left"])
                        ?? number(from: dict["x1"])
                    let y = number(from: dict["y"])
                        ?? number(from: dict["top"])
                        ?? number(from: dict["y1"])
                    let right = number(from: dict["right"]) ?? number(from: dict["x2"])
                    let bottom = number(from: dict["bottom"]) ?? number(from: dict["y2"])
                    var width = number(from: dict["width"]) ?? number(from: dict["w"])
                    var height = number(from: dict["height"]) ?? number(from: dict["h"])
                    if width == nil, let right, let x {
                        width = right - x
                    }
                    if height == nil, let bottom, let y {
                        height = bottom - y
                    }
                    if let x, let y, let width, let height {
                        return ReferenceImageCrop(x: x, y: y, width: width, height: height)
                    }
                } else if let array = json as? [Any], array.count >= 4 {
                    let values = array.compactMap { number(from: $0) }
                    if values.count >= 4 {
                        return ReferenceImageCrop(x: values[0], y: values[1], width: values[2], height: values[3])
                    }
                }
            }

            let separators = CharacterSet(charactersIn: ",|:")
            let parts = trimmed.components(separatedBy: separators).compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            if parts.count >= 4 {
                return ReferenceImageCrop(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
            }

            return nil
        }

        private static func number(from value: Any?) -> CGFloat? {
            switch value {
            case let number as NSNumber:
                return CGFloat(truncating: number)
            case let string as String:
                guard let value = Double(string.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    return nil
                }
                return CGFloat(value)
            default:
                return nil
            }
        }
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
        let success = await viewModel.uploadCapturedImage(token: authService.currentBearerToken())
        if success {
            try? await authService.fetchFrames()
            dismiss()
        }
    }

    private func resumePreviewIfNeeded() {
        guard !viewModel.captureManager.isRunning else { return }
        Task { await viewModel.updateCaptureConfiguration() }
    }

    private func currentPreviewOrientation() -> AVCaptureVideoOrientation {
        let orientation = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .interfaceOrientation
        switch orientation {
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        default:
            return fallbackPreviewOrientation()
        }
    }

    private func fallbackPreviewOrientation() -> AVCaptureVideoOrientation {
        switch UIDevice.current.orientation {
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .portrait:
            return .portrait
        default:
            return .landscapeRight
        }
    }
}

private struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let orientation: AVCaptureVideoOrientation
    let onPreviewLayerReady: (AVCaptureVideoPreviewLayer) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.configurePreviewConnection(orientation: orientation)
        onPreviewLayerReady(view.videoPreviewLayer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let previewView = uiView as? PreviewView else { return }
        previewView.videoPreviewLayer.session = session
        previewView.configurePreviewConnection(orientation: orientation)
        onPreviewLayerReady(previewView.videoPreviewLayer)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

private struct FrameLineOverlay: View {
    let configurations: [FrameLineConfiguration]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(Array(configurations.reversed())) { configuration in
                    if let aspectRatio = configuration.option.aspectRatio {
                        let rect = frameRect(in: proxy.size, aspectRatio: aspectRatio)
                        frameLinePath(in: rect, design: configuration.design)
                            .stroke(
                                configuration.color.swiftUIColor.opacity(configuration.opacity),
                                style: strokeStyle(for: configuration.design, thickness: configuration.thickness)
                            )
                    }
                }
            }
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

    private func frameLinePath(in rect: CGRect, design: FrameLineDesign) -> Path {
        switch design {
        case .solid, .dashed:
            return Path { path in
                path.addRect(rect)
            }
        case .brackets:
            return bracketPath(in: rect)
        }
    }

    private func bracketPath(in rect: CGRect) -> Path {
        let baseLength = min(rect.width, rect.height) * 0.08
        let cornerLength = max(12, min(28, baseLength))
        return Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerLength))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.minY))

            path.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cornerLength))

            path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerLength))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX - cornerLength, y: rect.maxY))

            path.move(to: CGPoint(x: rect.minX + cornerLength, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cornerLength))
        }
    }

    private func strokeStyle(for design: FrameLineDesign, thickness: Double) -> StrokeStyle {
        switch design {
        case .solid:
            return StrokeStyle(lineWidth: thickness, lineJoin: .round)
        case .dashed:
            return StrokeStyle(lineWidth: thickness, lineJoin: .round, dash: [8, 6])
        case .brackets:
            return StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round)
        }
    }
}

private struct FrameShadingOverlay: View {
    let configurations: [FrameLineConfiguration]

    var body: some View {
        GeometryReader { proxy in
            let rect = configurations
                .compactMap { configuration -> CGRect? in
                    guard let aspectRatio = configuration.option.aspectRatio else { return nil }
                    return frameRect(in: proxy.size, aspectRatio: aspectRatio)
                }
                .first
            if let rect {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: proxy.size))
                    path.addRect(rect)
                }
                .fill(.black.opacity(0.7), style: FillStyle(eoFill: true))
            }
        }
        .allowsHitTesting(false)
    }

    private func frameRect(in size: CGSize, aspectRatio: CGFloat) -> CGRect? {
        guard aspectRatio > 0 else { return nil }
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
    private var currentOrientation: AVCaptureVideoOrientation = .landscapeRight

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as? AVCaptureVideoPreviewLayer ?? AVCaptureVideoPreviewLayer()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        configurePreviewConnection(orientation: currentOrientation)
    }

    func configurePreviewConnection(orientation: AVCaptureVideoOrientation) {
        currentOrientation = orientation
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
