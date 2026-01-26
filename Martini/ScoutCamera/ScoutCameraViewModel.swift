import AVFoundation
import Foundation
import SwiftUI

@MainActor
final class ScoutCameraViewModel: ObservableObject {
    private enum PreferenceKey {
        static let showCrosshair = "scoutCameraShowCrosshair"
        static let showGrid = "scoutCameraShowGrid"
        static let showFrameShading = "scoutCameraShowFrameShading"
        static let selectedFrameLine = "scoutCameraSelectedFrameLine"
        static let selectedFrameLines = "scoutCameraSelectedFrameLines"
        static let frameLineConfigurations = "scoutCameraFrameLineConfigurations"
    }

    @Published var availableCameras: [DBCamera] = []
    @Published var availableLenses: [DBLens] = []
    @Published var availableModes: [DBCameraMode] = []
    @Published var availableLensPacks: [LensPackGroup] = []

    @Published var selectedCamera: DBCamera?
    @Published var selectedMode: DBCameraMode?
    @Published var selectedLens: DBLens?
    @Published var selectedLensPack: LensPackGroup?
    @Published var focalLengthMm: Double = 35
    @Published var frameLineConfigurations: [FrameLineConfiguration] {
        didSet {
            saveFrameLineConfigurations()
        }
    }
    @Published var showCrosshair: Bool {
        didSet { UserDefaults.standard.set(showCrosshair, forKey: preferenceKey(PreferenceKey.showCrosshair)) }
    }
    @Published var showGrid: Bool {
        didSet { UserDefaults.standard.set(showGrid, forKey: preferenceKey(PreferenceKey.showGrid)) }
    }
    @Published var showFrameShading: Bool {
        didSet { UserDefaults.standard.set(showFrameShading, forKey: preferenceKey(PreferenceKey.showFrameShading)) }
    }

    @Published var matchResult: FOVMatchResult?
    @Published var debugInfo: ScoutCameraDebugInfo?
    @Published var capturedImage: UIImage?
    @Published var processedImage: UIImage?
    @Published var isCapturing: Bool = false
    @Published var errorMessage: String?

    let captureManager = CaptureSessionManager()
    let calibrationStore = FOVCalibrationStore.shared
    let motionManager = MotionHeadingManager()
    let locationManager = ScoutLocationManager()

    private let projectId: String
    private let frameId: String
    private(set) var creativeId: String?
    private let targetAspectRatio: CGFloat
    private let dataStore = LocalJSONStore.shared
    private let selectionStore = ProjectKitSelectionStore.shared
    private let uploadService = FrameUploadService()

    init(projectId: String, frameId: String, creativeId: String?, targetAspectRatio: CGFloat) {
        self.projectId = projectId
        self.frameId = frameId
        self.creativeId = creativeId
        self.targetAspectRatio = targetAspectRatio
        self.showCrosshair = UserDefaults.standard.bool(forKey: preferenceKey(PreferenceKey.showCrosshair))
        self.showGrid = UserDefaults.standard.bool(forKey: preferenceKey(PreferenceKey.showGrid))
        self.showFrameShading = UserDefaults.standard.bool(forKey: preferenceKey(PreferenceKey.showFrameShading))
        self.frameLineConfigurations = Self.loadFrameLineConfigurations(projectId: projectId)
        loadData()
    }

    func updateCreativeId(_ creativeId: String?) {
        self.creativeId = creativeId
    }

    func startSensors() {
        motionManager.start()
        locationManager.start()
    }

    func stopSensors() {
        motionManager.stop()
        locationManager.stop()
    }

    func loadData() {
        let projectCameraIds = selectionStore.cameraIds(for: projectId)
        let projectLensIds = selectionStore.lensIds(for: projectId)
        availableCameras = projectCameraIds.isEmpty
            ? []
            : dataStore.fetchCameras(ids: projectCameraIds)
        availableLenses = projectLensIds.isEmpty
            ? []
            : dataStore.fetchLenses(ids: projectLensIds)
        if availableCameras.isEmpty || availableLenses.isEmpty {
            errorMessage = "Select cameras and lenses in Project Kit to use Scout Camera."
        } else {
            errorMessage = nil
        }
        availableLensPacks = buildLensPacks(from: availableLenses)
        selectedCamera = availableCameras.first
        selectedLens = availableLenses.first
        selectedLensPack = lensPackContainingSelectedLens() ?? availableLensPacks.first
        if let selectedLensPack,
           let lens = selectedLens,
           !selectedLensPack.lenses.contains(where: { $0.id == lens.id }) {
            selectedLens = selectedLensPack.lenses.first
        } else if selectedLensPack == nil {
            selectedLens = availableLenses.first
        }
        refreshModes()
        updateFocalLength()
        Task {
            await updateCaptureConfiguration()
        }
    }

    func refreshModes() {
        guard let selectedCamera else {
            availableModes = []
            selectedMode = nil
            return
        }
        availableModes = dataStore.fetchCameraModes(cameraId: selectedCamera.id)
        selectedMode = availableModes.first
    }

    func updateFocalLength() {
        guard let lens = selectedLens else { return }
        focalLengthMm = lens.focalLengthMm ?? lens.focalLengthMinMm ?? focalLengthMm
    }

    var activeFocalLengthMm: Double {
        currentFocalLength()
    }

    func selectNextLens() {
        guard let selectedLens else { return }
        if selectedLens.isZoom,
           let maxFocal = selectedLens.focalLengthMaxMm {
            let nextValue = min(maxFocal, focalLengthMm + 1)
            if nextValue != focalLengthMm {
                focalLengthMm = nextValue
            }
            return
        }
        let lensPool = selectedLensPack?.lenses ?? availableLenses
        guard let currentIndex = lensPool.firstIndex(where: { $0.id == selectedLens.id }) else {
            return
        }
        let nextIndex = min(currentIndex + 1, lensPool.count - 1)
        if nextIndex != currentIndex {
            self.selectedLens = lensPool[nextIndex]
        }
    }

    func selectPreviousLens() {
        guard let selectedLens else { return }
        if selectedLens.isZoom,
           let minFocal = selectedLens.focalLengthMinMm {
            let previousValue = max(minFocal, focalLengthMm - 1)
            if previousValue != focalLengthMm {
                focalLengthMm = previousValue
            }
            return
        }
        let lensPool = selectedLensPack?.lenses ?? availableLenses
        guard let currentIndex = lensPool.firstIndex(where: { $0.id == selectedLens.id }) else {
            return
        }
        let previousIndex = max(currentIndex - 1, 0)
        if previousIndex != currentIndex {
            self.selectedLens = lensPool[previousIndex]
        }
    }

    func updateCaptureConfiguration() async {
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if authStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                await updateCaptureConfiguration()
            } else {
                errorMessage = "Camera access is required to use Scout Camera."
            }
            return
        }

        guard authStatus == .authorized else {
            errorMessage = "Camera access is denied. Enable it in Settings."
            return
        }

        guard let mode = selectedMode, let lens = selectedLens else { return }
        let focal = currentFocalLength()
        let squeeze = effectiveSqueeze(mode: mode, lens: lens)
        let targetHFOV = FOVMath.horizontalFOV(sensorWidthMm: mode.sensorWidthMm, focalLengthMm: focal, squeeze: squeeze)
        let iphoneCameras = dataStore.fetchIPhoneCameras()
        let calibrationMultipliers = calibrationStore.multipliers
        let match = FOVEngine.matchIPhoneModule(
            targetHFOVRadians: targetHFOV,
            iphoneCameras: iphoneCameras,
            calibrationMultipliers: calibrationMultipliers
        )
        matchResult = match
        debugInfo = buildDebugInfo(
            targetHFOVRadians: targetHFOV,
            focalLengthMm: focal,
            match: match,
            iphoneCameras: iphoneCameras,
            calibrationMultipliers: calibrationMultipliers
        )

        let role = match?.cameraRole ?? "main"
        let zoom = match?.zoomFactor ?? 1.0
        do {
            try captureManager.configureSession(with: role, zoomFactor: zoom)
            captureManager.start()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func capturePhoto() {
        guard !isCapturing else { return }
        isCapturing = true
        processedImage = nil
        captureManager.capturePhoto { [weak self] image in
            guard let self else { return }
            guard let image else {
                Task { @MainActor in
                    self.errorMessage = "Failed to capture photo."
                    self.capturedImage = nil
                    self.processedImage = nil
                    self.isCapturing = false
                }
                return
            }
            Task { @MainActor in
                self.capturedImage = image
            }
            Task {
                let finalImage = await self.processImage(image)
                await MainActor.run {
                    self.processedImage = finalImage
                    self.isCapturing = false
                }
            }
        }
    }

    func processImage(_ image: UIImage) async -> UIImage? {
        guard let camera = selectedCamera, let mode = selectedMode, let lens = selectedLens else { return nil }
        let focalLabel = lensFocalLabel(lens: lens, focalLengthMm: focalLengthMm)
        let squeeze = effectiveSqueeze(mode: mode, lens: lens)
        let squeezeLabel = formattedSqueezeLabel(squeeze)
        let modeLabel = modeDisplayLabel(mode: mode)
        let cameraLine = buildCameraLine(camera: camera, modeLabel: modeLabel, squeezeLabel: squeezeLabel, squeeze: squeeze)
        let lensLine = buildLensLine(lens: lens, focalLabel: focalLabel, squeezeLabel: squeezeLabel, squeeze: squeeze)
        let metadata = ScoutPhotoMetadata(
            cameraLine: cameraLine,
            lensLine: lensLine
        )
        let logo = UIImage(named: "MartiniLogo")
        return PhotoProcessor.composeFinalImage(
            capturedImage: image,
            targetAspectRatio: targetAspectRatio,
            sensorAspectRatio: sensorAspectRatio,
            metadata: metadata,
            logoImage: logo,
            frameLineAspectRatio: primaryFrameLineOption.aspectRatio
        )
    }

    func uploadCapturedImage(token: String?) async -> Bool {
        guard let capturedImage else { return false }
        let finalImage: UIImage
        if let processedImage {
            finalImage = processedImage
        } else if let processed = await processImage(capturedImage) {
            finalImage = processed
        } else {
            finalImage = capturedImage
        }
        let resizedImage = resizedImageForUpload(from: finalImage, maxPixelDimension: 2000)
        guard let data = resizedImage.jpegData(compressionQuality: 0.85) else { return false }
        guard let creativeId else {
            errorMessage = "Missing creative ID for upload."
            return false
        }
        let metadata = metadataJSONString()
        do {
            try await uploadService.uploadPhotoboard(
                imageData: data,
                boardLabel: "Scout Camera",
                shootId: projectId,
                creativeId: creativeId,
                frameId: frameId,
                bearerToken: token,
                metadata: metadata
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func prepareShareImage() async -> UIImage? {
        if let processedImage {
            return processedImage
        }
        guard let capturedImage else { return nil }
        return await processImage(capturedImage)
    }

    private func metadataJSONString() -> String? {
        guard let camera = selectedCamera, let mode = selectedMode, let lens = selectedLens else { return nil }
        let squeeze = effectiveSqueeze(mode: mode, lens: lens)
        let frameLineData = frameLineConfigurations.map { configuration in
            compactMetadata([
                "id": configuration.id.uuidString,
                "label": configuration.option.rawValue,
                "aspect_ratio": configuration.option.aspectRatio,
                "color": configuration.color.rawValue,
                "opacity": configuration.opacity,
                "design": configuration.design.rawValue,
                "thickness": configuration.thickness
            ])
        }
        let extractionData: [String: Any]? = mode.extraction.map { hint in
            compactMetadata([
                "inside": hint.inside,
                "targets": hint.targets
            ])
        }
        let geoData: [String: Any]? = locationManager.location.map { location in
            compactMetadata([
                "latitude": location.coordinate.latitude,
                "longitude": location.coordinate.longitude,
                "altitude_m": location.altitude,
                "horizontal_accuracy_m": location.horizontalAccuracy,
                "vertical_accuracy_m": location.verticalAccuracy,
                "speed_mps": location.speed >= 0 ? location.speed : nil,
                "course_degrees": location.course >= 0 ? location.course : nil,
                "timestamp": ISO8601DateFormatter().string(from: location.timestamp)
            ])
        }
        let orientationData: [String: Any] = compactMetadata([
            "heading_degrees": motionManager.headingDegrees,
            "tilt_degrees": motionManager.tiltDegrees,
            "roll_degrees": motionManager.rollDegrees,
            "pitch_degrees": motionManager.pitchDegrees,
            "yaw_degrees": motionManager.yawDegrees
        ])
        let captureData: [String: Any] = compactMetadata([
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "focal_length_mm": focalLengthMm,
            "active_focal_length_mm": activeFocalLengthMm,
            "squeeze": squeeze,
            "selected_frame_line": primaryFrameLineOption.rawValue,
            "frame_line_aspect_ratio": primaryFrameLineOption.aspectRatio,
            "selected_frame_lines": activeFrameLineOptions.map(\.rawValue),
            "frame_line_aspect_ratios": activeFrameLineOptions.compactMap(\.aspectRatio),
            "framelines": frameLineData,
            "target_aspect_ratio": targetAspectRatio,
            "matched_camera_role": matchResult?.cameraRole,
            "matched_zoom_factor": matchResult?.zoomFactor,
            "geo": geoData,
            "orientation": orientationData
        ])
        let modeData: [String: Any] = compactMetadata([
            "id": mode.id,
            "name": mode.name,
            "sensor_width_mm": mode.sensorWidthMm,
            "sensor_height_mm": mode.sensorHeightMm,
            "resolution": mode.resolution,
            "aspect_ratio": mode.aspectRatio,
            "capture_gate": mode.captureGate,
            "anamorphic_preview_squeeze": mode.anamorphicPreviewSqueeze,
            "delivery_aspect_ratio": mode.deliveryAspectRatio,
            "recommended_lens_coverage": mode.recommendedLensCoverage,
            "vignette_risk": mode.vignetteRisk,
            "notes": mode.notes,
            "extraction": extractionData
        ])
        let cameraData: [String: Any] = compactMetadata([
            "id": camera.id,
            "brand": camera.brand,
            "model": camera.model,
            "sensor_type": camera.sensorType,
            "mount": camera.mount,
            "sensor_width_mm": camera.sensorWidthMm,
            "sensor_height_mm": camera.sensorHeightMm,
            "mode": modeData
        ])
        let lensData: [String: Any] = compactMetadata([
            "id": lens.id,
            "type": lens.type,
            "brand": lens.brand,
            "series": lens.series,
            "format": lens.format,
            "mounts": lens.mounts,
            "focal_length_mm": lens.focalLengthMm,
            "focal_length_min_mm": lens.focalLengthMinMm,
            "focal_length_max_mm": lens.focalLengthMaxMm,
            "max_t_stop": lens.maxTStop,
            "squeeze": lens.squeeze,
            "is_zoom": lens.isZoom
        ])
        let payload: [String: Any] = [
            "scout_camera": [
                [
                    "capture": [captureData],
                    "camera": [cameraData],
                    "lens": [lensData]
                ]
            ]
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func compactMetadata(_ values: [String: Any?]) -> [String: Any] {
        values.compactMapValues { $0 }
    }

    var activeFrameLineOptions: [FrameLineOption] {
        frameLineConfigurations.map(\.option)
    }

    var primaryFrameLineOption: FrameLineOption {
        frameLineConfigurations.first?.option ?? .none
    }

    var frameLineSummary: String {
        guard !frameLineConfigurations.isEmpty else { return FrameLineOption.none.rawValue }
        return frameLineConfigurations.map(\.option.rawValue).joined(separator: ", ")
    }

    func addFrameLineOption(_ option: FrameLineOption) {
        guard option != .none else { return }
        guard !frameLineConfigurations.contains(where: { $0.option == option }) else { return }
        frameLineConfigurations.append(FrameLineConfiguration(option: option))
    }

    func isFrameLineSelected(_ option: FrameLineOption) -> Bool {
        frameLineConfigurations.contains(where: { $0.option == option })
    }

    func removeFrameLineConfiguration(_ configuration: FrameLineConfiguration) {
        frameLineConfigurations.removeAll { $0.id == configuration.id }
    }

    func moveFrameLineConfigurations(from source: IndexSet, to destination: Int) {
        frameLineConfigurations.move(fromOffsets: source, toOffset: destination)
    }

    func binding(for configuration: FrameLineConfiguration) -> Binding<FrameLineConfiguration> {
        Binding {
            self.frameLineConfigurations.first(where: { $0.id == configuration.id }) ?? configuration
        } set: { updated in
            guard let index = self.frameLineConfigurations.firstIndex(where: { $0.id == configuration.id }) else {
                return
            }
            self.frameLineConfigurations[index] = updated
        }
    }

    private func resizedImageForUpload(from image: UIImage, maxPixelDimension: CGFloat) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let maxDimension = max(pixelWidth, pixelHeight)
        guard maxDimension > maxPixelDimension else { return image }
        let scaleRatio = maxPixelDimension / maxDimension
        let targetSize = CGSize(width: pixelWidth * scaleRatio, height: pixelHeight * scaleRatio)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func currentFocalLength() -> Double {
        guard let lens = selectedLens else {
            return focalLengthMm
        }
        if lens.isZoom {
            return focalLengthMm
        }
        return lens.focalLengthMm ?? lens.focalLengthMinMm ?? focalLengthMm
    }

    private func lensFocalLabel(lens: DBLens, focalLengthMm: Double) -> String {
        if lens.isZoom, let min = lens.focalLengthMinMm, let max = lens.focalLengthMaxMm {
            return "\(Int(min))–\(Int(max))mm @ \(Int(focalLengthMm))mm"
        }
        if let focal = lens.focalLengthMm ?? lens.focalLengthMinMm {
            return "\(Int(focal))mm"
        }
        return "\(Int(focalLengthMm))mm"
    }

    private func saveFrameLineConfigurations() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(frameLineConfigurations) {
            UserDefaults.standard.set(data, forKey: preferenceKey(PreferenceKey.frameLineConfigurations))
        }
    }

    private static func loadFrameLineConfigurations(projectId: String) -> [FrameLineConfiguration] {
        let decoder = JSONDecoder()
        let scopedFrameLineKey = preferenceKey(PreferenceKey.frameLineConfigurations, projectId: projectId)
        if let data = UserDefaults.standard.data(forKey: scopedFrameLineKey),
           let decoded = try? decoder.decode([FrameLineConfiguration].self, from: data) {
            return decoded
        }
        if let savedRawValues = UserDefaults.standard.stringArray(
            forKey: preferenceKey(PreferenceKey.selectedFrameLines, projectId: projectId)
        ) {
            let savedOptions = savedRawValues.compactMap(FrameLineOption.init(rawValue:))
            return savedOptions.filter { $0 != .none }.map { FrameLineConfiguration(option: $0) }
        }
        if let rawValue = UserDefaults.standard.string(
            forKey: preferenceKey(PreferenceKey.selectedFrameLine, projectId: projectId)
        ),
           let savedOption = FrameLineOption(rawValue: rawValue),
           savedOption != .none {
            return [FrameLineConfiguration(option: savedOption)]
        }
        return []
    }

    private func preferenceKey(_ key: String) -> String {
        Self.preferenceKey(key, projectId: projectId)
    }

    private static func preferenceKey(_ key: String, projectId: String) -> String {
        "\(key)_\(projectId)"
    }

    private func effectiveSqueeze(mode: DBCameraMode, lens: DBLens) -> Double {
        if abs(lens.squeeze - 1.0) > 0.001 {
            return lens.squeeze
        }
        if let modeSqueeze = mode.anamorphicPreviewSqueeze {
            return modeSqueeze
        }
        return 1.0
    }

    private func formattedSqueezeLabel(_ squeeze: Double) -> String {
        if abs(squeeze.rounded() - squeeze) < 0.01 {
            return "\(Int(squeeze.rounded()))x"
        }
        return String(format: "%.1fx", squeeze)
    }

    private func modeDisplayLabel(mode: DBCameraMode) -> String {
        if let captureGate = mode.captureGate, mode.name.count > 24 {
            return captureGate
        }
        return mode.name
    }

    private func buildCameraLine(camera: DBCamera, modeLabel: String, squeezeLabel: String, squeeze: Double) -> String {
        if squeeze > 1.0 {
            return "\(camera.model) • \(modeLabel) (\(squeezeLabel) Anamorphic)"
        }
        return "\(camera.model) • \(modeLabel)"
    }

    private func buildLensLine(lens: DBLens, focalLabel: String, squeezeLabel: String, squeeze: Double) -> String {
        let lensName = "\(lens.brand) \(lens.series)"
        if squeeze > 1.0 {
            return "\(lensName) • \(focalLabel) • \(squeezeLabel)"
        }
        return "\(lensName) • \(focalLabel)"
    }

    func selectLensPack(_ pack: LensPackGroup) {
        selectedLensPack = pack
        if let selectedLens,
           pack.lenses.contains(where: { $0.id == selectedLens.id }) {
            return
        }
        selectedLens = pack.lenses.first
    }

    private func lensPackContainingSelectedLens() -> LensPackGroup? {
        guard let selectedLens else { return nil }
        return availableLensPacks.first { pack in
            pack.lenses.contains(where: { $0.id == selectedLens.id })
        }
    }

    private func buildLensPacks(from lenses: [DBLens]) -> [LensPackGroup] {
        let lensLookup = Dictionary(uniqueKeysWithValues: lenses.map { ($0.id, $0) })
        let itemsByPack = Dictionary(grouping: dataStore.lensPackItems, by: \.packId)
        var packs: [LensPackGroup] = dataStore.lensPacks.compactMap { pack in
            let sortedItems = (itemsByPack[pack.id] ?? []).sorted { $0.sortOrder < $1.sortOrder }
            let packLenses = sortedItems.compactMap { lensLookup[$0.lensId] }
            guard !packLenses.isEmpty else { return nil }
            return LensPackGroup(id: pack.id, displayName: "\(pack.brand) \(pack.name)", lenses: packLenses)
        }

        let assignedLensIds = Set(packs.flatMap(\.lenses).map(\.id))
        let unassigned = lenses
            .filter { !assignedLensIds.contains($0.id) }
            .sorted { "\($0.brand) \($0.series)" < "\($1.brand) \($1.series)" }
        if !unassigned.isEmpty {
            packs.append(LensPackGroup(id: "selected_lenses", displayName: "Selected Lenses", lenses: unassigned))
        }
        return packs.sorted { $0.displayName < $1.displayName }
    }

    var sensorAspectRatio: CGFloat? {
        guard let mode = selectedMode else { return nil }
        if mode.sensorWidthMm > 0, mode.sensorHeightMm > 0 {
            return CGFloat(mode.sensorWidthMm / mode.sensorHeightMm)
        }
        return parseAspectRatio(mode.aspectRatio)
    }

    private func parseAspectRatio(_ ratio: String?) -> CGFloat? {
        guard let ratio else { return nil }
        let cleaned = ratio.lowercased().replacingOccurrences(of: " ", with: "")
        if cleaned.contains(":") {
            let parts = cleaned.split(separator: ":")
            if parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]), h != 0 {
                return CGFloat(w / h)
            }
        }
        if cleaned.contains("x") {
            let parts = cleaned.split(separator: "x")
            if parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]), h != 0 {
                return CGFloat(w / h)
            }
        }
        if let value = Double(cleaned), value > 0 {
            return CGFloat(value)
        }
        return nil
    }

    private func buildDebugInfo(
        targetHFOVRadians: Double,
        focalLengthMm: Double,
        match: FOVMatchResult?,
        iphoneCameras: [DBIPhoneCamera],
        calibrationMultipliers: [String: Double]
    ) -> ScoutCameraDebugInfo? {
        guard let match else { return nil }
        let targetHFOVDegrees = FOVMath.radiansToDegrees(targetHFOVRadians)
        let camera = iphoneCameras.first { $0.cameraRole == match.cameraRole }
        let nativeHFOVDegrees = camera.map {
            FOVEngine.calibratedHFOVDegrees(camera: $0, calibrationMultipliers: calibrationMultipliers)
        } ?? 0
        let achievedHFOVDegrees = match.zoomFactor > 0 ? nativeHFOVDegrees / match.zoomFactor : 0
        let errorDegrees = abs(achievedHFOVDegrees - targetHFOVDegrees)
        let candidates = buildDebugCandidates(
            iphoneCameras: iphoneCameras,
            targetHFOVRadians: targetHFOVRadians,
            targetHFOVDegrees: targetHFOVDegrees,
            calibrationMultipliers: calibrationMultipliers
        )
        return ScoutCameraDebugInfo(
            targetHFOVDegrees: targetHFOVDegrees,
            achievedHFOVDegrees: achievedHFOVDegrees,
            errorDegrees: errorDegrees,
            cameraRole: match.cameraRole,
            zoomFactor: match.zoomFactor,
            focalLengthMm: focalLengthMm,
            candidates: candidates
        )
    }

    private func buildDebugCandidates(
        iphoneCameras: [DBIPhoneCamera],
        targetHFOVRadians: Double,
        targetHFOVDegrees: Double,
        calibrationMultipliers: [String: Double]
    ) -> [ScoutCameraFOVCandidate] {
        guard targetHFOVRadians > 0 else { return [] }
        return iphoneCameras.map { camera in
            let calibratedHFOVDegrees = FOVEngine.calibratedHFOVDegrees(
                camera: camera,
                calibrationMultipliers: calibrationMultipliers
            )
            let nativeHFOVRadians = FOVMath.degreesToRadians(calibratedHFOVDegrees)
            let requiredZoom = nativeHFOVRadians / targetHFOVRadians
            let clampedZoom = min(max(requiredZoom, camera.minZoom), camera.maxZoom)
            let achievedHFOVDegrees = clampedZoom > 0 ? calibratedHFOVDegrees / clampedZoom : 0
            let errorDegrees = abs(achievedHFOVDegrees - targetHFOVDegrees)
            return ScoutCameraFOVCandidate(
                cameraRole: camera.cameraRole,
                nativeHFOVDegrees: calibratedHFOVDegrees,
                requiredZoom: requiredZoom,
                clampedZoom: clampedZoom,
                minZoom: camera.minZoom,
                maxZoom: camera.maxZoom,
                achievedHFOVDegrees: achievedHFOVDegrees,
                errorDegrees: errorDegrees
            )
        }
        .sorted { $0.errorDegrees < $1.errorDegrees }
    }
}

struct LensPackGroup: Identifiable, Hashable {
    let id: String
    let displayName: String
    let lenses: [DBLens]
}

struct ScoutCameraDebugInfo: Equatable {
    let targetHFOVDegrees: Double
    let achievedHFOVDegrees: Double
    let errorDegrees: Double
    let cameraRole: String
    let zoomFactor: Double
    let focalLengthMm: Double
    let candidates: [ScoutCameraFOVCandidate]
}

struct ScoutCameraFOVCandidate: Equatable {
    let cameraRole: String
    let nativeHFOVDegrees: Double
    let requiredZoom: Double
    let clampedZoom: Double
    let minZoom: Double
    let maxZoom: Double
    let achievedHFOVDegrees: Double
    let errorDegrees: Double
}

enum FrameLineOption: String, CaseIterable, Identifiable, Codable {
    case none = "Off"
    case ratio16_9 = "16:9"
    case ratio1_85 = "1.85:1"
    case ratio2_0 = "2.00:1"
    case ratio2_39 = "2.39:1"
    case ratio4_3 = "4:3"
    case ratio9_16 = "9:16"
    case ratio4_5 = "4:5"
    case ratio1_1 = "1:1"
    case ratio3_4 = "3:4"
    case ratio3_2 = "3:2"
    case ratio5_4 = "5:4"
    case ratio1_90 = "1.90:1"
    case ratio17_9 = "17:9"

    var id: String { rawValue }

    private enum CodingKeys: String, CodingKey {
        case rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "9:16", "0.56":
            self = .ratio9_16
            return
        case "1.00":
            self = .ratio1_1
            return
        case "1.33":
            self = .ratio4_3
            return
        case "1.66":
            self = .ratio16_9
            return
        case "1.78":
            self = .ratio16_9
            return
        case "1.85":
            self = .ratio1_85
            return
        case "2.00":
            self = .ratio2_0
            return
        case "2.39":
            self = .ratio2_39
            return
        case "0.67":
            self = .ratio3_4
            return
        default:
            break
        }
        guard let option = FrameLineOption(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid FrameLineOption: \(rawValue)")
        }
        self = option
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var aspectRatio: CGFloat? {
        switch self {
        case .none:
            return nil
        case .ratio16_9:
            return 16.0 / 9.0
        case .ratio1_85:
            return 1.85
        case .ratio2_0:
            return 2.0
        case .ratio2_39:
            return 2.39
        case .ratio4_3:
            return 4.0 / 3.0
        case .ratio9_16:
            return 9.0 / 16.0
        case .ratio4_5:
            return 4.0 / 5.0
        case .ratio1_1:
            return 1.0
        case .ratio3_4:
            return 3.0 / 4.0
        case .ratio3_2:
            return 3.0 / 2.0
        case .ratio5_4:
            return 5.0 / 4.0
        case .ratio1_90:
            return 1.90
        case .ratio17_9:
            return 17.0 / 9.0
        }
    }

    var descriptionText: String? {
        switch self {
        case .none:
            return nil
        case .ratio16_9:
            return "Standard (HD / Streaming)"
        case .ratio1_85:
            return "Flat (Theatrical)"
        case .ratio2_0:
            return "Univisium"
        case .ratio2_39:
            return "Scope (Anamorphic)"
        case .ratio4_3:
            return "Classic / Archive"
        case .ratio9_16:
            return "Vertical Video (Reels / TikTok)"
        case .ratio4_5:
            return "Instagram Feed"
        case .ratio1_1:
            return "Square"
        case .ratio3_4:
            return "Vertical Photo"
        case .ratio3_2:
            return "Photography"
        case .ratio5_4:
            return "Print / Editorial"
        case .ratio1_90:
            return "IMAX Digital"
        case .ratio17_9:
            return "DCI Native"
        }
    }
}

enum FrameLineColor: String, CaseIterable, Identifiable, Codable {
    case white
    case red
    case green
    case blue
    case orange
    case pink
    case purple

    var id: String { rawValue }

    static func selectableColors(including current: FrameLineColor) -> [FrameLineColor] {
        let filtered = allCases.filter { $0 != .pink }
        if current == .pink {
            return filtered + [.pink]
        }
        return filtered
    }

    var displayName: String {
        rawValue.capitalized
    }

    var swiftUIColor: Color {
        switch self {
        case .white:
            return .white
        case .red:
            return .red
        case .green:
            return .green
        case .blue:
            return .blue
        case .orange:
            return .orange
        case .pink:
            return .pink
        case .purple:
            return .purple
        }
    }
}

enum FrameLineDesign: String, CaseIterable, Identifiable, Codable {
    case solid
    case dashed
    case brackets

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .solid:
            return "Solid"
        case .dashed:
            return "Dashed"
        case .brackets:
            return "Brackets"
        }
    }

    var symbolName: String {
        switch self {
        case .solid:
            return "rectangle"
        case .dashed:
            return "rectangle.dashed"
        case .brackets:
            return "viewfinder.rectangular"
        }
    }
}

struct FrameLineConfiguration: Identifiable, Codable, Equatable {
    let id: UUID
    var option: FrameLineOption
    var color: FrameLineColor
    var opacity: Double
    var design: FrameLineDesign
    var thickness: Double

    init(
        id: UUID = UUID(),
        option: FrameLineOption,
        color: FrameLineColor = .white,
        opacity: Double = 0.8,
        design: FrameLineDesign = .solid,
        thickness: Double = 2
    ) {
        self.id = id
        self.option = option
        self.color = color
        self.opacity = opacity
        self.design = design
        self.thickness = thickness
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case option
        case color
        case opacity
        case design
        case thickness
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        option = try container.decode(FrameLineOption.self, forKey: .option)
        color = try container.decode(FrameLineColor.self, forKey: .color)
        opacity = try container.decode(Double.self, forKey: .opacity)
        design = try container.decode(FrameLineDesign.self, forKey: .design)
        thickness = try container.decodeIfPresent(Double.self, forKey: .thickness) ?? 2
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(option, forKey: .option)
        try container.encode(color, forKey: .color)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(design, forKey: .design)
        try container.encode(thickness, forKey: .thickness)
    }
}
