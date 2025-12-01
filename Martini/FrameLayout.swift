import SwiftUI
import UIKit

struct FrameLayout: View {
    let frame: Frame
    var title: String?
    var subtitle: String?
    var showStatusBadge: Bool = true
    var showFrameNumberOverlay: Bool = true
    var cornerRadius: CGFloat = 8

    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.colorScheme) private var colorScheme

    private var resolvedTitle: String? {
        if let title, !title.isEmpty {
            return title
        }
        return nil
    }

    private var resolvedSubtitle: String? {
        if let subtitle, !subtitle.isEmpty {
            return subtitle
        }

        return nil
    }

    var body: some View {
        let layout: AnyLayout = (hSizeClass == .regular)
        ? AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))

        layout {
            imageCard
            textBlock
        }
    }

    private var imageCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.gray.opacity(0.2))
                .overlay(
                    Group {
                        if let urlString = frame.board ?? frame.boardThumb, let url = URL(string: urlString) {
                            CachedAsyncImage(url: url) { phase in
                                switch phase {
                                case let .success(image):
                                    AnyView(
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    )
                                case .empty:
                                    AnyView(ProgressView())
                                case .failure:
                                    AnyView(placeholder)
                                @unknown default:
                                    AnyView(placeholder)
                                }
                            }
                        } else {
                            placeholder
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

            if showFrameNumberOverlay {
                GeometryReader { geo in
                    let diameter = max(18, geo.size.width * 0.08) // 8% of width with a minimum

                    VStack {
                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.8))
                                    .frame(width: diameter, height: diameter)
                                Text(frameNumberText)
                                    .font(.system(size: diameter * 0.53, weight: .semibold))
                                    .foregroundColor(.white)
                                    .minimumScaleFactor(0.5)
                            }
                        }
                        .padding(max(2, diameter * 0.25))
                        Spacer()
                    }
                }
            }

            if showStatusBadge {
                statusOverlay(for: frame.statusEnum)
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        )
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let resolvedTitle {
                if let attributedTitle = attributedString(fromHTML: resolvedTitle) {
                    Text(attributedTitle)
                        .font(.system(size: 14, weight: .semibold))
                } else {
                    Text(resolvedTitle)
                        .font(.system(size: 14, weight: .semibold))
                }
            }

            if let resolvedSubtitle {
                let subtitleSize = dynamicSubtitleFontSize(for: 200)
                if let attributedSubtitle = attributedString(fromHTML: resolvedSubtitle, defaultColor: defaultDescriptionUIColor) {
                    Text(attributedSubtitle)
                        .font(.system(size: subtitleSize, weight: .semibold))
                        .foregroundColor(descriptionColor)
                } else {
                    Text(resolvedSubtitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(descriptionColor)
                        //.lineLimit(2)
                }
            }
        }
    }

    private var borderWidth: CGFloat {
        frame.statusEnum != .none ? 3 : 1
    }

    private var borderColor: Color {
        let status = frame.statusEnum

        switch status {
        case .done:
            return .red
        case .inProgress:
            return .green
        case .skip:
            return .red
        case .upNext:
            return .orange
        case .none:
            return .gray.opacity(0.3)
        }
    }

    private var statusText: String? {
        let text = frame.status?.uppercased() ?? ""
        return text.isEmpty ? nil : text
    }

    private var frameNumberLabel: String? {
        frame.frameNumber > 0 ? "Frame #\(frame.frameNumber)" : nil
    }

    private var frameNumberText: String {
        frame.frameNumber > 0 ? "\(frame.frameNumber)" : "--"
    }

    @ViewBuilder
    private func statusOverlay(for status: FrameStatus) -> some View {
        switch status {
        case .done:
            // Red X lines from corner to corner
            GeometryReader { geometry in
                ZStack {
                    // Diagonal line from top-left to bottom-right
                    Path { path in
                        path.move(to: .zero)
                        path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                    }
                    .stroke(Color.red, lineWidth: 5)

                    // Diagonal line from top-right to bottom-left
                    Path { path in
                        path.move(to: CGPoint(x: geometry.size.width, y: 0))
                        path.addLine(to: CGPoint(x: 0, y: geometry.size.height))
                    }
                    .stroke(Color.red, lineWidth: 5)
                }
            }
            .aspectRatio(aspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

        case .skip:
            // Red transparent layer
            Color.red.opacity(0.3)
                .cornerRadius(cornerRadius)

        case .inProgress, .upNext, .none:
            EmptyView()
        }
    }

    private var placeholder: some View {
        VStack {
            Image(systemName: "photo")
                .font(.system(size: 40))
                .foregroundColor(.gray.opacity(0.5))
            if showFrameNumberOverlay, let frameNumberLabel {
                Text(frameNumberLabel)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }

    private func attributedString(fromHTML html: String, defaultColor: UIColor? = nil) -> AttributedString? {
        // 1) Preserve line breaks by converting common HTML breaks/blocks to \n
        var text = html
            .replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)

        // Treat common block-level tags as line breaks
        let blockTags = ["</p>", "</div>", "</li>", "</h1>", "</h2>", "</h3>", "</h4>", "</h5>", "</h6>"]
        for tag in blockTags {
            text = text.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }

        // 2) Strip all remaining HTML tags
        // This regex removes anything that looks like <...>
        let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: [])
        let range = NSRange(location: 0, length: (text as NSString).length)
        let stripped = regex?.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "") ?? text

        // 3) Decode basic HTML entities
        let decoded = stripped
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")

        // 4) Collapse multiple consecutive newlines to a single newline
        let collapsed = decoded.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)

        // Return as a plain AttributedString (no styles), letting caller apply font/color
        return AttributedString(collapsed)
    }

    private var descriptionColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var defaultDescriptionUIColor: UIColor {
        .white
    }

    private var aspectRatio: CGFloat {
        guard let ratioString = frame.creativeAspectRatio,
              let parsedRatio = FrameLayout.aspectRatio(from: ratioString) else {
            return 16.0 / 9.0
        }

        return parsedRatio
    }

    private static func aspectRatio(from ratioString: String) -> CGFloat? {
        let separators = CharacterSet(charactersIn: ":/xX").union(.whitespaces)
        let components = ratioString
            .split(whereSeparator: { separator in
                separator.unicodeScalars.contains { separators.contains($0) }
            })
            .map(String.init)

        guard components.count == 2,
              let width = Double(components[0]),
              let height = Double(components[1]),
              height != 0 else {
            return nil
        }

        return CGFloat(width / height)
    }
    
    private func dynamicSubtitleFontSize(for width: CGFloat) -> CGFloat {
        // Proportional scaling: ~5% of available width
        let proportional = width * 0.05
        // Clamp to sensible bounds
        let minSize: CGFloat = 4
        let maxSize: CGFloat = 20
        return max(minSize, min(proportional, maxSize))
    }
}

