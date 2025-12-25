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

            let logoRect = CGRect(x: 20, y: availableHeight + (stripHeight - 32) / 2, width: 120, height: 32)
            if let logoImage {
                logoImage.draw(in: logoRect, blendMode: .normal, alpha: 1)
            }

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .right

            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraphStyle
            ]

            let detailAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .regular),
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraphStyle
            ]

            let rightMargin: CGFloat = 20
            let textWidth: CGFloat = canvasWidth - logoRect.maxX - rightMargin - 16
            let cameraLine = "\(metadata.cameraName) • \(metadata.cameraModeName)"
            let lensLine = "\(metadata.lensName) • \(metadata.focalLengthLabel) • \(metadata.squeezeLabel)"

            let cameraLineRect = CGRect(
                x: logoRect.maxX + 16,
                y: availableHeight + 12,
                width: textWidth,
                height: 22
            )
            cameraLine.draw(in: cameraLineRect, withAttributes: textAttributes)

            let lensLineRect = CGRect(
                x: logoRect.maxX + 16,
                y: cameraLineRect.maxY + 4,
                width: textWidth,
                height: 20
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
