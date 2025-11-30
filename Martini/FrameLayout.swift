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
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case let .success(image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                case .empty:
                                    ProgressView()
                                case .failure:
                                    placeholder
                                @unknown default:
                                    placeholder
                                }
                            }
                        } else {
                            placeholder
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

            if showFrameNumberOverlay {
                VStack {
                    HStack {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.8))
                                .frame(width: 34, height: 34)
                            Text(frameNumberText)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(10)
                    Spacer()
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
                if let attributedSubtitle = attributedString(fromHTML: resolvedSubtitle, defaultColor: defaultDescriptionUIColor) {
                    Text(attributedSubtitle)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                } else {
                    Text(resolvedSubtitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(descriptionColor)
                        .lineLimit(2)
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
        guard let data = html.data(using: .utf8) else { return nil }

        do {
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ]

            let nsAttributedString = try NSMutableAttributedString(
                data: data,
                options: options,
                documentAttributes: nil
            )

            if let defaultColor = defaultColor {
                let fullRange = NSRange(location: 0, length: nsAttributedString.length)
                // Force a consistent text color so descriptions remain readable even when
                // HTML supplies its own (potentially dark) foreground colors.
                nsAttributedString.addAttribute(.foregroundColor, value: defaultColor, range: fullRange)
            }

            return AttributedString(nsAttributedString)
        } catch {
            return nil
        }
    }

    private var descriptionColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var defaultDescriptionUIColor: UIColor {
        colorScheme == .dark ? .white : .black
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
}
