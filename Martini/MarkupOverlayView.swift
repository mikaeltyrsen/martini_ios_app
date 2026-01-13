import PencilKit
import SwiftUI

struct MarkupOverlayView: View {
    let drawing: PKDrawing
    var contentMode: ContentMode = .fit
    var canvasSize: CGSize? = nil

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            if size.width > 0, size.height > 0 {
                let scaledDrawing = scaledDrawing(for: size)
                Image(uiImage: scaledDrawing.image(from: CGRect(origin: .zero, size: size), scale: UIScreen.main.scale))
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            }
        }
        .allowsHitTesting(false)
    }

    private func scaledDrawing(for size: CGSize) -> PKDrawing {
        guard let canvasSize,
              canvasSize.width > 0,
              canvasSize.height > 0,
              size.width > 0,
              size.height > 0 else {
            return drawing
        }

        let scaleX = size.width / canvasSize.width
        let scaleY = size.height / canvasSize.height
        if abs(scaleX - 1) < 0.001, abs(scaleY - 1) < 0.001 {
            return drawing
        }

        return drawing.transformed(using: CGAffineTransform(scaleX: scaleX, y: scaleY))
    }
}
