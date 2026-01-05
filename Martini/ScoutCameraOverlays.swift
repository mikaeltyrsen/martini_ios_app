import SwiftUI

struct FrameShadingOverlay: View {
    let configurations: [FrameLineConfiguration]

    var body: some View {
        GeometryReader { proxy in
            let rect = configurations
                .compactMap { configuration -> CGRect? in
                    guard let aspectRatio = configuration.option.aspectRatio else { return nil }
                    return frameRect(in: proxy.size, aspectRatio: aspectRatio)
                }
                .first
            if let rect {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: proxy.size))
                    path.addRect(rect)
                }
                .fill(.black.opacity(0.7), style: FillStyle(eoFill: true))
            }
        }
        .allowsHitTesting(false)
    }

    private func frameRect(in size: CGSize, aspectRatio: CGFloat) -> CGRect? {
        guard aspectRatio > 0 else { return nil }
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
}

struct GridOverlay: View {
    let aspectRatio: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            let rect = aspectRatio.map { frameRect(in: proxy.size, aspectRatio: $0) }
                ?? CGRect(origin: .zero, size: proxy.size)
            let oneThirdWidth = rect.width / 3
            let oneThirdHeight = rect.height / 3
            Path { path in
                path.move(to: CGPoint(x: rect.minX + oneThirdWidth, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.minX + oneThirdWidth, y: rect.maxY))
                path.move(to: CGPoint(x: rect.minX + oneThirdWidth * 2, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.minX + oneThirdWidth * 2, y: rect.maxY))

                path.move(to: CGPoint(x: rect.minX, y: rect.minY + oneThirdHeight))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + oneThirdHeight))
                path.move(to: CGPoint(x: rect.minX, y: rect.minY + oneThirdHeight * 2))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + oneThirdHeight * 2))
            }
            .stroke(.white.opacity(0.6), lineWidth: 1)
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
}

struct CrosshairOverlay: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let centerX = width / 2
            let centerY = height / 2
            let length: CGFloat = min(width, height) * 0.08
            Path { path in
                path.move(to: CGPoint(x: centerX - length, y: centerY))
                path.addLine(to: CGPoint(x: centerX + length, y: centerY))
                path.move(to: CGPoint(x: centerX, y: centerY - length))
                path.addLine(to: CGPoint(x: centerX, y: centerY + length))
            }
            .stroke(.white.opacity(0.8), lineWidth: 1.5)
        }
        .allowsHitTesting(false)
    }
}
