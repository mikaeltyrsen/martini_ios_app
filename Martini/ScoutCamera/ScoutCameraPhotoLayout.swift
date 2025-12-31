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
        let baseImage = cropImage(capturedImage, to: sensorAspectRatio)
        let inputSize = baseImage.size
        guard inputSize.width > 0, inputSize.height > 0 else { return nil }

        let canvasWidth = inputSize.width
        let canvasHeight = canvasWidth / targetAspectRatio
        let canvasSize = CGSize(width: canvasWidth, height: canvasHeight)
        let stripHeight = max(canvasHeight * 0.12, 60)
        let availableHeight = canvasHeight - stripHeight

        let scale = min(canvasWidth / inputSize.width, availableHeight / inputSize.height)
        let scaledSize = CGSize(width: inputSize.width * scale, height: inputSize.height * scale)
        let imageOrigin = CGPoint(
            x: (canvasWidth - scaledSize.width) / 2,
            y: (availableHeight - scaledSize.height) / 2
        )

        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: canvasSize))

            baseImage.draw(in: CGRect(origin: imageOrigin, size: scaledSize))

            if let frameLineAspectRatio {
                let frameContainer = CGRect(origin: imageOrigin, size: scaledSize)
                let frameRect = frameLineRect(
                    container: frameContainer,
                    aspectRatio: frameLineAspectRatio
                )
                let framePath = UIBezierPath(rect: frameRect)
                UIColor.white.withAlphaComponent(0.8).setStroke()
                framePath.lineWidth = 3
                framePath.stroke()
            }

            let stripRect = CGRect(x: 0, y: availableHeight, width: canvasWidth, height: stripHeight)
            UIColor.white.setFill()
            context.fill(stripRect)

            let logoRect = CGRect(x: 20, y: availableHeight + (stripHeight - 32) / 2, width: 240, height: 64)
            if let logoImage {
                let tintedLogo = logoImage.withTintColor(.black, renderingMode: .alwaysOriginal)
                tintedLogo.draw(in: logoRect, blendMode: .normal, alpha: 1)
            }

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .right

            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 28, weight: .semibold),
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraphStyle
            ]

            let detailAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .regular),
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraphStyle
            ]

            let rightMargin: CGFloat = 20
            let textWidth: CGFloat = canvasWidth - logoRect.maxX - rightMargin - 16
            let cameraLine = metadata.cameraLine
            let lensLine = metadata.lensLine

            let cameraLineRect = CGRect(
                x: logoRect.maxX + 16,
                y: availableHeight + 12,
                width: textWidth,
                height: 40
            )
            cameraLine.draw(in: cameraLineRect, withAttributes: textAttributes)

            let lensLineRect = CGRect(
                x: logoRect.maxX + 16,
                y: cameraLineRect.maxY + 4,
                width: textWidth,
                height: 30
            )
            lensLine.draw(in: lensLineRect, withAttributes: detailAttributes)
        }
    }

    private static func frameLineRect(container: CGRect, aspectRatio: CGFloat) -> CGRect {
        let containerAspect = container.width / max(container.height, 1)
        let width: CGFloat
        let height: CGFloat
        if containerAspect > aspectRatio {
            height = container.height
            width = height * aspectRatio
        } else {
            width = container.width
            height = width / aspectRatio
        }
        return CGRect(
            x: container.midX - width / 2,
            y: container.midY - height / 2,
            width: width,
            height: height
        )
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
            logoImage: sampleLogo(),
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

    private func sampleLogo() -> UIImage {
        let size = CGSize(width: 240, height: 64)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let text = "MARTINI"
            let textSize = text.size(withAttributes: attributes)
            let textOrigin = CGPoint(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2
            )
            text.draw(at: textOrigin, withAttributes: attributes)
        }
    }
}

struct ScoutCameraPhotoLayout_Previews: PreviewProvider {
    static var previews: some View {
        ScoutCameraPhotoLayoutPreview()
    }
}
#endif
