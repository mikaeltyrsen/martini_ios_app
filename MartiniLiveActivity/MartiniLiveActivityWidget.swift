//
//  MartiniLiveActivityWidget.swift
//  MartiniLiveActivity
//

import ActivityKit
import SwiftUI
import WidgetKit
#if canImport(UIKit)
import UIKit
#endif

@available(iOS 16.1, *)
struct MartiniLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MartiniLiveActivityAttributes.self) { context in
            LiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "photo")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(.white)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    LiveActivityFrameProgressBadge(
                        currentFrame: context.state.currentFrame,
                        nextFrame: context.state.nextFrame,
                        completed: context.state.completed,
                        total: context.state.total,
                        size: 44
                    )
                }

                DynamicIslandExpandedRegion(.bottom) {
                    LiveActivityProgressView(completed: context.state.completed, total: context.state.total)
                }
            } compactLeading: {
                ZStack {
                        Color.clear // keeps layout stable
                        Image("MartiniLogoIconOnly")
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } compactTrailing: {
                LiveActivityFrameProgressBadge(
                    currentFrame: context.state.currentFrame,
                    nextFrame: context.state.nextFrame,
                    completed: context.state.completed,
                    total: context.state.total,
                    size: 24
                )
            } minimal: {
                ZStack {
                        Color.clear // keeps layout stable
                        Image("MartiniLogoIconOnly")
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }
}

@available(iOS 16.1, *)
private struct LiveActivityView: View {
    let context: ActivityViewContext<MartiniLiveActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image("MartiniLogoIconOnly")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundStyle(.primary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.projectTitle)
                            .font(.system(size: 16, weight: .semibold, design: .default))
                            .foregroundColor(.primary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .truncationMode(.tail)
                    }
                    .layoutPriority(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .top, spacing: 8) {
                    if let currentFrame = context.state.currentFrame {
                        LiveActivityFrameCard(
                            label: "Here",
                            frame: currentFrame,
                            borderColor: .green,
                            iconName: "video.fill"
                        )
                    }
                    if let nextFrame = context.state.nextFrame {
                        LiveActivityFrameCard(
                            label: "Next",
                            frame: nextFrame,
                            borderColor: .orange,
                            iconName: "forward.fill"
                        )
                    }
                }
            }

            LiveActivityProgressView(completed: context.state.completed, total: context.state.total)
                .frame(height: 20)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
    }
}

@available(iOS 16.1, *)
private struct LiveActivityFrameCard: View {
    let label: String
    let frame: MartiniLiveActivityFrame?
    let borderColor: Color
    let iconName: String

    private let thumbnailMaxWidth: CGFloat = 100
    private let thumbnailMaxHeight: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(borderColor)

                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(borderColor)
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .background(
                Capsule()
                    .fill(borderColor.opacity(0.15))
            )
            .fixedSize(horizontal: true, vertical: true)

            LiveActivityFrameThumbnail(
                frame: frame,
                borderColor: borderColor,
                maxWidth: thumbnailMaxWidth,
                maxHeight: thumbnailMaxHeight
            )
        }
    }
}

@available(iOS 16.1, *)
private struct LiveActivityProgressView: View {
    let completed: Int
    let total: Int

    struct ThickProgressViewStyle: ProgressViewStyle {
        var height: CGFloat = 8
        var cornerRadius: CGFloat = 100
        
        func makeBody(configuration: Configuration) -> some View {
            GeometryReader { geo in
                let fraction = CGFloat(configuration.fractionCompleted ?? 0)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: height)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.primary)
                        .frame(width: geo.size.width * fraction, height: height)
                }
            }
        }
    }
    
    var body: some View {
        let safeTotal = max(total, 1)

        ProgressView(value: Double(completed), total: Double(safeTotal))
            .progressViewStyle(ThickProgressViewStyle(height: 8))
            .frame(height: 20)
    }
}

@available(iOS 16.1, *)
private struct LiveActivityFrameThumbnail: View {
    let frame: MartiniLiveActivityFrame?
    let borderColor: Color
    let maxWidth: CGFloat
    let maxHeight: CGFloat

    private let cornerRadius = 8.0
    private let borderWidth = 2.0
    private let defaultAspectRatio: CGFloat = 16.0 / 9.0

    @State private var displayImage: Image?

    var body: some View {
        let thumbnailSize = fittedThumbnailSize
        ZStack(alignment: .topTrailing) {
            thumbnailView
                .frame(width: thumbnailSize.width, height: thumbnailSize.height, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(borderColor, lineWidth: borderWidth)
                )

            if let numberText = frameNumberText {
                Text(numberText)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.black.opacity(0.8))
                    .clipShape(Circle())
                    .padding(4)
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let displayImage {
            displayImage
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else if thumbnailUrl != nil {
            placeholderView
                .task(id: taskIdentifier) {
                    await loadImage()
                }
        } else {
            placeholderView
        }
    }

    private var placeholderView: some View {
        ZStack {
            Color.secondary.opacity(0.2)
            Image(systemName: "photo")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var frameNumberText: String? {
        guard let frame, frame.number > 0 else { return nil }
        return String(frame.number)
    }

    private var thumbnailUrl: URL? {
        guard let urlString = frame?.thumbnailUrl else { return nil }
        if let url = URL(string: urlString) {
            return url
        }
        if let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            return URL(string: encoded)
        }
        return nil
    }

    private var taskIdentifier: String {
        let urlValue = frame?.thumbnailUrl ?? ""
        return "\(urlValue)-\(frame?.crop ?? "")"
    }

    private var fittedThumbnailSize: CGSize {
        let ratio = max(frameAspectRatio ?? defaultAspectRatio, 0.01)
        let containerAspect = maxWidth / max(maxHeight, 1)
        if containerAspect > ratio {
            let height = maxHeight
            return CGSize(width: height * ratio, height: height)
        }
        let width = maxWidth
        return CGSize(width: width, height: width / ratio)
    }

    private var frameAspectRatio: CGFloat? {
        parseAspectRatio(frame?.creativeAspectRatio)
    }

    private func loadImage() async {
        guard let url = thumbnailUrl else {
            await MainActor.run { displayImage = nil }
            return
        }
        await MainActor.run { displayImage = nil }
        guard let loadedImage = await loadUIImage(from: url) else {
            await MainActor.run { displayImage = nil }
            return
        }

        let croppedImage = cropImage(loadedImage, crop: frame?.crop) ?? loadedImage
        await MainActor.run {
            displayImage = Image(uiImage: croppedImage)
        }
    }

    private func loadUIImage(from url: URL) async -> UIImage? {
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        request.setValue("MartiniLiveActivity/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
                let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length") ?? "\(data.count)"
                print("🧩 LiveActivity thumbnail response: status=\(httpResponse.statusCode) bytes=\(data.count) content-length=\(contentLength) content-type=\(contentType)")
                if !(200...299).contains(httpResponse.statusCode) {
                    return nil
                }
            } else {
                print("🧩 LiveActivity thumbnail response: non-http-response bytes=\(data.count)")
            }
            if data.isEmpty {
                print("🧩 LiveActivity thumbnail response: empty-body url=\(url.absoluteString)")
                return nil
            }
            return UIImage(data: data)
        } catch {
            print("🧩 LiveActivity thumbnail error: \(error.localizedDescription) url=\(url.absoluteString)")
            return nil
        }
    }

    private func cropImage(_ image: UIImage, crop: String?) -> UIImage? {
        guard let cropRect = parseCrop(crop), let cgImage = image.cgImage else { return nil }
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        var rect = cropRect.rect(in: CGSize(width: imageWidth, height: imageHeight))
        rect = rect.intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
        guard rect.width > 1, rect.height > 1 else { return nil }
        guard let cropped = cgImage.cropping(to: rect.integral) else { return nil }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    private func parseCrop(_ value: String?) -> ReferenceImageCrop? {
        guard let value, !value.isEmpty else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) {
            if let dict = json as? [String: Any] {
                let x = number(from: dict["x"])
                    ?? number(from: dict["left"])
                    ?? number(from: dict["x1"])
                let y = number(from: dict["y"])
                    ?? number(from: dict["top"])
                    ?? number(from: dict["y1"])
                let right = number(from: dict["right"]) ?? number(from: dict["x2"])
                let bottom = number(from: dict["bottom"]) ?? number(from: dict["y2"])
                var width = number(from: dict["width"]) ?? number(from: dict["w"])
                var height = number(from: dict["height"]) ?? number(from: dict["h"])
                if width == nil, let right, let x {
                    width = right - x
                }
                if height == nil, let bottom, let y {
                    height = bottom - y
                }
                if let x, let y, let width, let height {
                    return ReferenceImageCrop(x: x, y: y, width: width, height: height)
                }
            } else if let array = json as? [Any], array.count >= 4 {
                let values = array.compactMap { number(from: $0) }
                if values.count >= 4 {
                    return ReferenceImageCrop(x: values[0], y: values[1], width: values[2], height: values[3])
                }
            }
        }

        let separators = CharacterSet(charactersIn: ",|:")
        let parts = trimmed.components(separatedBy: separators).compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if parts.count >= 4 {
            return ReferenceImageCrop(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
        }

        return nil
    }

    private func number(from value: Any?) -> CGFloat? {
        switch value {
        case let number as NSNumber:
            return CGFloat(truncating: number)
        case let string as String:
            guard let value = Double(string.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return nil
            }
            return CGFloat(value)
        default:
            return nil
        }
    }

    private func parseAspectRatio(_ ratioString: String?) -> CGFloat? {
        guard let ratioString else { return nil }
        let trimmed = ratioString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let ratio = Double(trimmed), ratio > 0 {
            return CGFloat(ratio)
        }

        let separators = CharacterSet(charactersIn: "x:/")
        let parts = trimmed.components(separatedBy: separators).compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if parts.count >= 2, parts[0] > 0, parts[1] > 0 {
            return CGFloat(parts[0] / parts[1])
        }

        return nil
    }

    private var accessibilityLabel: String {
        guard let frame else { return "No frame" }
        if frame.number > 0 {
            return "Frame \(frame.number), \(frame.title)"
        }
        return frame.title
    }
}

@available(iOS 16.1, *)
private struct ReferenceImageCrop {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    func rect(in size: CGSize) -> CGRect {
        let imageWidth = max(size.width, 1)
        let imageHeight = max(size.height, 1)

        var cropX = x
        var cropY = y
        var cropWidth = width
        var cropHeight = height

        if cropWidth <= 1, cropHeight <= 1 {
            cropX *= imageWidth
            cropY *= imageHeight
            cropWidth *= imageWidth
            cropHeight *= imageHeight
        } else if cropWidth <= 100, cropHeight <= 100 {
            cropX = cropX / 100 * imageWidth
            cropY = cropY / 100 * imageHeight
            cropWidth = cropWidth / 100 * imageWidth
            cropHeight = cropHeight / 100 * imageHeight
        }

        cropWidth = max(1, min(cropWidth, imageWidth))
        cropHeight = max(1, min(cropHeight, imageHeight))
        cropX = max(0, min(cropX, imageWidth - cropWidth))
        cropY = max(0, min(cropY, imageHeight - cropHeight))

        return CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
    }
}

@available(iOS 16.1, *)
private struct LiveActivityFrameProgressBadge: View {
    let currentFrame: MartiniLiveActivityFrame?
    let nextFrame: MartiniLiveActivityFrame?
    let completed: Int
    let total: Int
    let size: CGFloat

    var body: some View {
        let safeTotal = max(total, 1)
        let progress = min(max(Double(completed) / Double(safeTotal), 0), 1)

        ZStack {
            Circle()
                .stroke(activeColor.opacity(0.15), lineWidth: size * 0.14)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    activeColor.opacity(1),
                    style: StrokeStyle(lineWidth: size * 0.14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text(progressLabel)
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(activeColor)
                .minimumScaleFactor(0.5)
        }
        .frame(width: size, height: size)
        .padding(2)
    }

    private var progressLabel: String {
        guard let frame, frame.number > 0 else { return "-" }
        return String(frame.number)
    }

    private var activeColor: Color {
        if currentFrame?.number ?? 0 > 0 {
            return .green
        }
        if nextFrame?.number ?? 0 > 0 {
            return .orange
        }
        return .gray
    }

    private var frame: MartiniLiveActivityFrame? {
        currentFrame ?? nextFrame
    }
}

@available(iOS 16.1, *)
private struct LiveActivityMinimalBadge: View {
    let frame: MartiniLiveActivityFrame?

    var body: some View {
        Text(frameNumber)
            .font(.caption.weight(.semibold))
    }

    private var frameNumber: String {
        guard let frame, frame.number > 0 else { return "-" }
        return String(frame.number)
    }
}

#if DEBUG
@available(iOS 16.1, *)
#Preview("Live Activity", as: .content, using: previewAttributes) {
    MartiniLiveActivityWidget()
} contentStates: {
    previewContentState
}

@available(iOS 16.1, *)
#Preview("Dynamic Island Expanded", as: .dynamicIsland(.expanded), using: previewAttributes) {
    MartiniLiveActivityWidget()
} contentStates: {
    previewContentState
}

@available(iOS 16.1, *)
#Preview("Dynamic Island Compact", as: .dynamicIsland(.compact), using: previewAttributes) {
    MartiniLiveActivityWidget()
} contentStates: {
    previewContentState
}

@available(iOS 16.1, *)
#Preview("Dynamic Island Minimal", as: .dynamicIsland(.minimal), using: previewAttributes) {
    MartiniLiveActivityWidget()
} contentStates: {
    previewContentState
}

@available(iOS 16.1, *)
private var previewAttributes: MartiniLiveActivityAttributes {
    MartiniLiveActivityAttributes(projectTitle: "Espresso Sprint")
}

@available(iOS 16.1, *)
private var previewContentState: MartiniLiveActivityAttributes.ContentState {
    MartiniLiveActivityAttributes.ContentState(
        currentFrame: MartiniLiveActivityFrame(
            id: "frame-12",
            title: "Storyboard",
            number: 12,
            thumbnailUrl: nil,
            creativeAspectRatio: "2.39",
            crop: nil
        ),
        nextFrame: MartiniLiveActivityFrame(
            id: "frame-13",
            title: "Animatic",
            number: 13,
            thumbnailUrl: nil,
            creativeAspectRatio: "2.39",
            crop: nil
        ),
        completed: 12,
        total: 48
    )
}
#endif
