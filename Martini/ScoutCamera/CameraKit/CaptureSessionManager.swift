import AVFoundation
import UIKit

final class CaptureSessionManager: ObservableObject {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var inFlightProcessor: PhotoCaptureProcessor?

    @Published var isRunning: Bool = false

    func configureSession(with role: String, zoomFactor: Double) throws {
        session.beginConfiguration()
        session.sessionPreset = .photo

        if let currentInput {
            session.removeInput(currentInput)
            self.currentInput = nil
        }

        guard let device = CameraDeviceSelector.device(for: role) else {
            session.commitConfiguration()
            throw NSError(domain: "CaptureSessionManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Camera device not available"])
        }

        let input = try AVCaptureDeviceInput(device: device)
        if session.canAddInput(input) {
            session.addInput(input)
            currentInput = input
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        session.commitConfiguration()

        if let connection = photoOutput.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = .landscapeRight
        }

        try device.lockForConfiguration()
        let clampedZoom = min(max(zoomFactor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
        device.videoZoomFactor = CGFloat(clampedZoom)
        device.unlockForConfiguration()
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
}
