import UIKit
#if DEBUG
import SwiftUI
#endif

struct ScoutCameraPhotoLayout {
    static func render(
        capturedImage: UIImage,
        targetAspectRatio: CGFloat,
        sensorAspectRatio: CGFloat?,
        metadata: ScoutPhotoMetadata,
        logoImage: UIImage?,
        frameLineAspectRatio: CGFloat?
    ) -> UIImage? {
        let outputAspectRatio = sensorAspectRatio ?? targetAspectRatio
        return cropImage(capturedImage, to: outputAspectRatio)
    }

    private static func cropImage(_ image: UIImage, to aspectRatio: CGFloat?) -> UIImage {
        guard let aspectRatio, aspectRatio > 0 else { return image }
        guard let cgImage = image.cgImage else { return image }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        guard width > 0, height > 0 else { return image }

        let currentRatio = width / height
        let cropRect: CGRect
        if currentRatio > aspectRatio {
            let targetWidth = height * aspectRatio
            let x = (width - targetWidth) / 2
            cropRect = CGRect(x: x, y: 0, width: targetWidth, height: height)
        } else {
            let targetHeight = width / aspectRatio
            let y = (height - targetHeight) / 2
            cropRect = CGRect(x: 0, y: y, width: width, height: targetHeight)
        }

        guard let cropped = cgImage.cropping(to: cropRect.integral) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }
}

#if DEBUG
private struct ScoutCameraPhotoLayoutPreview: View {
    private let metadata = ScoutPhotoMetadata(
        cameraLine: "ScoutCam • 24fps • 8K",
        lensLine: "50mm ƒ/1.4 • ISO 400"
    )

    var body: some View {
        let previewImage = ScoutCameraPhotoLayout.render(
            capturedImage: sampleImage(),
            targetAspectRatio: 4 / 5,
            sensorAspectRatio: 3 / 2,
            metadata: metadata,
            logoImage: nil,
            frameLineAspectRatio: 16 / 9
        )

        return Group {
            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFit()
                    .background(Color(.secondarySystemBackground))
            } else {
                Text("Failed to render preview")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }

    private func sampleImage() -> UIImage {
        let size = CGSize(width: 1200, height: 800)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let insetRect = CGRect(x: 80, y: 60, width: 1040, height: 680)
            UIColor.systemIndigo.setFill()
            context.fill(insetRect)

            let accentRect = CGRect(x: 140, y: 120, width: 240, height: 140)
            UIColor.systemOrange.setFill()
            context.fill(accentRect)
        }
    }

}

struct ScoutCameraPhotoLayout_Previews: PreviewProvider {
    static var previews: some View {
        ScoutCameraPhotoLayoutPreview()
    }
}
#endif
