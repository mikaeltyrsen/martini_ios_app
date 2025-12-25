import AVFoundation

enum CameraDeviceSelector {
    static func device(for role: String) -> AVCaptureDevice? {
        let deviceType: AVCaptureDevice.DeviceType
        switch role {
        case "ultra":
            deviceType = .builtInUltraWideCamera
        case "tele":
            deviceType = .builtInTelephotoCamera
        default:
            deviceType = .builtInWideAngleCamera
        }

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [deviceType],
            mediaType: .video,
            position: .back
        )
        return discovery.devices.first
    }
}
