import SwiftUI

struct FrameLineOverlayView: View {
    let configurations: [FrameLineConfiguration]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(Array(configurations.reversed())) { configuration in
                    if let aspectRatio = configuration.option.aspectRatio {
                        let rect = frameRect(in: proxy.size, aspectRatio: aspectRatio)
                        frameLinePath(in: rect, design: configuration.design)
                            .stroke(
                                configuration.color.swiftUIColor.opacity(configuration.opacity),
                                style: strokeStyle(for: configuration.design, thickness: configuration.thickness)
                            )
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func frameRect(in size: CGSize, aspectRatio: CGFloat) -> CGRect {
        let containerAspect = size.width / max(size.height, 1)
        let width: CGFloat
        let height: CGFloat
        if containerAspect > aspectRatio {
            height = size.height
            width = height * aspectRatio
        } else {
            width = size.width
            height = width / aspectRatio
        }
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    private func frameLinePath(in rect: CGRect, design: FrameLineDesign) -> Path {
        switch design {
        case .solid, .dashed:
            return Path { path in
                path.addRect(rect)
            }
        case .brackets:
            return bracketPath(in: rect)
        }
    }

    private func bracketPath(in rect: CGRect) -> Path {
        let baseLength = min(rect.width, rect.height) * 0.08
        let cornerLength = max(12, min(28, baseLength))
        return Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerLength))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.minY))

            path.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cornerLength))

            path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerLength))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX - cornerLength, y: rect.maxY))

            path.move(to: CGPoint(x: rect.minX + cornerLength, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cornerLength))
        }
    }

    private func strokeStyle(for design: FrameLineDesign, thickness: Double) -> StrokeStyle {
        switch design {
        case .solid:
            return StrokeStyle(lineWidth: thickness, lineJoin: .round)
        case .dashed:
            return StrokeStyle(lineWidth: thickness, lineJoin: .round, dash: [8, 6])
        case .brackets:
            return StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round)
        }
    }
}
