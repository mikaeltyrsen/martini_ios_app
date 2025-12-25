import UIKit

struct ScoutPhotoMetadata {
    let cameraName: String
    let cameraModeName: String
    let lensName: String
    let focalLengthLabel: String
    let squeezeLabel: String
}

struct PhotoProcessor {
    static func composeFinalImage(
        capturedImage: UIImage,
        targetAspectRatio: CGFloat,
        sensorAspectRatio: CGFloat?,
        metadata: ScoutPhotoMetadata,
        logoImage: UIImage?,
        frameLineAspectRatio: CGFloat?
    ) -> UIImage? {
        ScoutCameraPhotoLayout.render(
            capturedImage: capturedImage,
            targetAspectRatio: targetAspectRatio,
            sensorAspectRatio: sensorAspectRatio,
            metadata: metadata,
            logoImage: logoImage,
            frameLineAspectRatio: frameLineAspectRatio
        )
    }
}
