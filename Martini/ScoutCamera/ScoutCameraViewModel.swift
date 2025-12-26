import Foundation
import SwiftUI
import AVFoundation

@MainActor
final class ScoutCameraViewModel: ObservableObject {
    @Published var availableCameras: [DBCamera] = []
    @Published var availableLenses: [DBLens] = []
    @Published var availableModes: [DBCameraMode] = []
    @Published var availableLensPacks: [LensPackGroup] = []

    @Published var selectedCamera: DBCamera?
    @Published var selectedMode: DBCameraMode?
    @Published var selectedLens: DBLens?
    @Published var selectedLensPack: LensPackGroup?
    @Published var focalLengthMm: Double = 35
    @Published var selectedFrameLine: FrameLineOption = .none
    @Published var showCrosshair: Bool = false
    @Published var showGrid: Bool = false
    @Published var showFrameShading: Bool = false

    @Published var matchResult: FOVMatchResult?
    @Published var debugInfo: ScoutCameraDebugInfo?
    @Published var capturedImage: UIImage?
    @Published var processedImage: UIImage?
    @Published var isCapturing: Bool = false
    @Published var errorMessage: String?

    let captureManager = CaptureSessionManager()
    let calibrationStore = FOVCalibrationStore.shared

    private let projectId: String
    private let frameId: String
    private let targetAspectRatio: CGFloat
    private let dataStore = LocalJSONStore.shared
    private let selectionStore = ProjectKitSelectionStore.shared
    private let uploadService = FrameUploadService()

    init(projectId: String, frameId: String, targetAspectRatio: CGFloat) {
        self.projectId = projectId
        self.frameId = frameId
        self.targetAspectRatio = targetAspectRatio
        loadData()
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
        captureManager.capturePhoto { [weak self] image in
            guard let self else { return }
            Task { @MainActor in
                guard let image else {
                    self.errorMessage = "Failed to capture photo."
                    self.capturedImage = nil
                    self.isCapturing = false
                    return
                }
                self.capturedImage = image
                self.processedImage = await self.processImage(image)
                self.isCapturing = false
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
        let logo = UIImage(named: "martini-logo")
        return PhotoProcessor.composeFinalImage(
            capturedImage: image,
            targetAspectRatio: targetAspectRatio,
            sensorAspectRatio: sensorAspectRatio,
            metadata: metadata,
            logoImage: logo,
            frameLineAspectRatio: selectedFrameLine.aspectRatio
        )
    }

    func uploadProcessedImage(token: String?) async -> Bool {
        guard let processedImage, let data = processedImage.jpegData(compressionQuality: 0.9) else { return false }
        do {
            try await uploadService.uploadPhotoboard(
                imageData: data,
                label: "Photoboard",
                projectId: projectId,
                frameId: frameId,
                bearerToken: token
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
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

enum FrameLineOption: String, CaseIterable, Identifiable {
    case none = "Off"
    case ratio1_33 = "1.33"
    case ratio1_66 = "1.66"
    case ratio1_78 = "1.78"
    case ratio1_85 = "1.85"
    case ratio2_0 = "2.00"
    case ratio2_39 = "2.39"

    var id: String { rawValue }

    var aspectRatio: CGFloat? {
        switch self {
        case .none:
            return nil
        case .ratio1_33:
            return 1.33
        case .ratio1_66:
            return 1.66
        case .ratio1_78:
            return 1.78
        case .ratio1_85:
            return 1.85
        case .ratio2_0:
            return 2.0
        case .ratio2_39:
            return 2.39
        }
    }
}
