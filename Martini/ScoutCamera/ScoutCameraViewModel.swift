import Foundation
import SwiftUI

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
    private let database = LocalDatabase.shared
    private let uploadService = FrameUploadService()

    init(projectId: String, frameId: String, targetAspectRatio: CGFloat) {
        self.projectId = projectId
        self.frameId = frameId
        self.targetAspectRatio = targetAspectRatio
        loadData()
    }

    func loadData() {
        let projectCameraIds = database.fetchProjectCameraIds(projectId: projectId)
        let projectLensIds = database.fetchProjectLensIds(projectId: projectId)
        availableCameras = projectCameraIds.isEmpty
            ? []
            : database.fetchCameras(ids: projectCameraIds)
        availableLenses = projectLensIds.isEmpty
            ? []
            : database.fetchLenses(ids: projectLensIds)
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
        availableModes = database.fetchCameraModes(cameraId: selectedCamera.id)
        selectedMode = availableModes.first
    }

    func updateFocalLength() {
        guard let lens = selectedLens else { return }
        focalLengthMm = lens.focalLengthMinMm
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
        let iphoneModel = IPhoneCameraModelResolver.currentModelName()
        let iphoneCameras = database.fetchIPhoneCameras(model: iphoneModel)
        let match = FOVEngine.matchIPhoneModule(targetHFOVRadians: targetHFOV, iphoneCameras: iphoneCameras)
        matchResult = match

        let role = match?.cameraRole ?? "main"
        let zoom = match?.zoomFactor ?? 1.0
        do {
            try captureManager.configureSession(with: role, zoomFactor: zoom)
            captureManager.start()
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
        let focalLabel = lens.isZoom ? "\(Int(lens.focalLengthMinMm))–\(Int(lens.focalLengthMaxMm))mm @ \(Int(focalLengthMm))mm" : "\(Int(focalLengthMm))mm"
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
        if let lens = selectedLens, lens.isZoom {
            return focalLengthMm
        }
        return selectedLens?.focalLengthMinMm ?? focalLengthMm
    }
}
