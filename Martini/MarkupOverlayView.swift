import PencilKit
import SwiftUI

struct MarkupOverlayView: View {
    let drawing: PKDrawing
    var contentMode: ContentMode = .fit

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            if size.width > 0, size.height > 0 {
                Image(uiImage: drawing.image(from: CGRect(origin: .zero, size: size), scale: UIScreen.main.scale))
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            }
        }
        .allowsHitTesting(false)
    }
}
