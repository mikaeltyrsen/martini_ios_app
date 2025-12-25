import Foundation
import SwiftUI
import AVFoundation

@MainActor
final class ScoutCameraViewModel: ObservableObject {
    @Published var availableCameras: [DBCamera] = []
    @Published var availableLenses: [DBLens] = []
    @Published var availableModes: [DBCameraMode] = []

    @Published var selectedCamera: DBCamera?
    @Published var selectedMode: DBCameraMode?
    @Published var selectedLens: DBLens?
    @Published var focalLengthMm: Double = 35
    @Published var selectedFrameLine: FrameLineOption = .none

    @Published var matchResult: FOVMatchResult?
    @Published var debugInfo: ScoutCameraDebugInfo?
    @Published var capturedImage: UIImage?
    @Published var processedImage: UIImage?
    @Published var isCapturing: Bool = false
    @Published var errorMessage: String?

    let captureManager = CaptureSessionManager()

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
        selectedCamera = availableCameras.first
        selectedLens = availableLenses.first
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
        guard let selectedLens,
              let currentIndex = availableLenses.firstIndex(where: { $0.id == selectedLens.id }) else {
            return
        }
        let nextIndex = min(currentIndex + 1, availableLenses.count - 1)
        if nextIndex != currentIndex {
            self.selectedLens = availableLenses[nextIndex]
        }
    }

    func selectPreviousLens() {
        guard let selectedLens,
              let currentIndex = availableLenses.firstIndex(where: { $0.id == selectedLens.id }) else {
            return
        }
        let previousIndex = max(currentIndex - 1, 0)
        if previousIndex != currentIndex {
            self.selectedLens = availableLenses[previousIndex]
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
        let targetHFOV = FOVMath.horizontalFOV(sensorWidthMm: mode.sensorWidthMm, focalLengthMm: focal, squeeze: lens.squeeze)
        let iphoneCameras = dataStore.fetchIPhoneCameras()
        let match = FOVEngine.matchIPhoneModule(targetHFOVRadians: targetHFOV, iphoneCameras: iphoneCameras)
        matchResult = match
        debugInfo = buildDebugInfo(
            targetHFOVRadians: targetHFOV,
            focalLengthMm: focal,
            match: match,
            iphoneCameras: iphoneCameras
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
        let metadata = ScoutPhotoMetadata(
            cameraName: "\(camera.model)",
            cameraModeName: mode.name,
            lensName: "\(lens.brand) \(lens.series)",
            focalLengthLabel: focalLabel,
            squeezeLabel: String(format: "%.1fx", lens.squeeze)
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
        iphoneCameras: [DBIPhoneCamera]
    ) -> ScoutCameraDebugInfo? {
        guard let match else { return nil }
        let targetHFOVDegrees = FOVMath.radiansToDegrees(targetHFOVRadians)
        let camera = iphoneCameras.first { $0.cameraRole == match.cameraRole }
        let nativeHFOVDegrees = camera?.nativeHFOVDegrees ?? 0
        let achievedHFOVDegrees = match.zoomFactor > 0 ? nativeHFOVDegrees / match.zoomFactor : 0
        let errorDegrees = abs(achievedHFOVDegrees - targetHFOVDegrees)
        return ScoutCameraDebugInfo(
            targetHFOVDegrees: targetHFOVDegrees,
            achievedHFOVDegrees: achievedHFOVDegrees,
            errorDegrees: errorDegrees,
            cameraRole: match.cameraRole,
            zoomFactor: match.zoomFactor,
            focalLengthMm: focalLengthMm
        )
    }
}

struct ScoutCameraDebugInfo: Equatable {
    let targetHFOVDegrees: Double
    let achievedHFOVDegrees: Double
    let errorDegrees: Double
    let cameraRole: String
    let zoomFactor: Double
    let focalLengthMm: Double
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
