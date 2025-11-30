import SwiftUI

struct FrameLayout: View {
    let frame: Frame
    var title: String?
    var subtitle: String?
    var showStatusBadge: Bool = true
    var showFrameNumberOverlay: Bool = true
    var cornerRadius: CGFloat = 8

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
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(16/9, contentMode: .fit)
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
                        Spacer()
                        Text(frameNumberText)
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(4)
                            .padding(4)
                    }
                }

                if showStatusBadge {
                    statusOverlay(for: frame.statusEnum)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )

            if let resolvedTitle {
                Text(resolvedTitle)
                    .font(.headline)
            }

            if let resolvedSubtitle {
                Text(resolvedSubtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            if showStatusBadge || showFrameNumberOverlay {
                HStack(spacing: 12) {
                    if showStatusBadge, let status = statusText {
                        Text(status)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(borderColor)
                            .cornerRadius(4)
                    }

                    if showFrameNumberOverlay, let frameNumberLabel {
                        Text(frameNumberLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
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
            .aspectRatio(16/9, contentMode: .fit)

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
}
