import AVFoundation
import UIKit

final class CaptureSessionManager: ObservableObject {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var inFlightProcessor: PhotoCaptureProcessor?

    @Published var isRunning: Bool = false
    private var currentOrientation: AVCaptureVideoOrientation = .landscapeRight

    func configureSession(with role: String, zoomFactor: Double) throws {
        guard let device = CameraDeviceSelector.device(for: role) else {
            throw NSError(domain: "CaptureSessionManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Camera device not available"])
        }
        let needsInputUpdate = currentInput?.device.uniqueID != device.uniqueID
        let needsOutputUpdate = !session.outputs.contains(photoOutput)

        if needsInputUpdate || needsOutputUpdate {
            session.beginConfiguration()
            session.sessionPreset = .photo

            if needsInputUpdate, let currentInput {
                session.removeInput(currentInput)
                self.currentInput = nil
            }

            if needsInputUpdate {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input) {
                    session.addInput(input)
                    currentInput = input
                }
            }

            if needsOutputUpdate, session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
            }

            session.commitConfiguration()
        }

        updateVideoOrientation(currentOrientation)

        let activeDevice = currentInput?.device ?? device
        try activeDevice.lockForConfiguration()
        let clampedZoom = min(max(zoomFactor, activeDevice.minAvailableVideoZoomFactor), activeDevice.maxAvailableVideoZoomFactor)
        activeDevice.videoZoomFactor = CGFloat(clampedZoom)
        activeDevice.unlockForConfiguration()
    }

    func start() {
        guard !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
            DispatchQueue.main.async {
                self?.isRunning = true
            }
        }
    }

    func stop() {
        guard session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.stopRunning()
            DispatchQueue.main.async {
                self?.isRunning = false
            }
        }
    }

    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        let settings = AVCapturePhotoSettings()
        let processor = PhotoCaptureProcessor { [weak self] image in
            completion(image)
            self?.inFlightProcessor = nil
        }
        inFlightProcessor = processor
        photoOutput.capturePhoto(with: settings, delegate: processor)
    }

    func focus(at point: CGPoint) {
        guard let device = currentInput?.device else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
                if device.isFocusModeSupported(.autoFocus) {
                    device.focusMode = .autoFocus
                }
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
            }
        } catch {
            return
        }
    }

    func updateVideoOrientation(_ orientation: AVCaptureVideoOrientation) {
        currentOrientation = orientation
        if let connection = photoOutput.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = orientation
        }
    }

    func restartSessionForOrientationChange() {
        guard session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.session.stopRunning()
            self.session.startRunning()
            DispatchQueue.main.async {
                self.isRunning = self.session.isRunning
            }
        }
    }
}
