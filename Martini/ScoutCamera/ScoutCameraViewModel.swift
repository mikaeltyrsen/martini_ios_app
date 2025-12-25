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

    @Published var matchResult: FOVMatchResult?
    @Published var capturedImage: UIImage?
    @Published var processedImage: UIImage?
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
        captureManager.capturePhoto { [weak self] image in
            guard let self else { return }
            Task { @MainActor in
                guard let image else {
                    self.errorMessage = "Failed to capture photo."
                    return
                }
                self.capturedImage = image
                self.processedImage = await self.processImage(image)
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
            metadata: metadata,
            logoImage: logo
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
}
