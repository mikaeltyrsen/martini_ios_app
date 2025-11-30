import SwiftUI

struct FrameView: View {
    let frame: Frame
    let onClose: () -> Void
    @State private var selectedStatus: FrameStatus

    init(frame: Frame, onClose: @escaping () -> Void) {
        self.frame = frame
        self.onClose = onClose
        _selectedStatus = State(initialValue: frame.statusEnum)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
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
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                            statusOverlay(for: frame.statusEnum)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(borderColor, lineWidth: borderWidth)
                        )

                        if let caption = primaryText, !caption.isEmpty {
                            Text(caption)
                                .font(.headline)
                        }

                        if let secondary = secondaryText, !secondary.isEmpty {
                            Text(secondary)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Frame \(frame.frameNumber > 0 ? String(frame.frameNumber) : "")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Picker("Status", selection: $selectedStatus) {
                        Text("Done").tag(FrameStatus.done)
                        Text("Here").tag(FrameStatus.inProgress)
                        Text("Next").tag(FrameStatus.upNext)
                        Text("Omit").tag(FrameStatus.skip)
                        Text("Clear").tag(FrameStatus.none)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: .infinity)
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onClose() }
                }
            }
            .tint(.accentColor)
        }
    }

    private var borderWidth: CGFloat { frame.statusEnum != .none ? 3 : 1 }

    private var borderColor: Color {
        switch frame.statusEnum {
        case .done: return .red
        case .inProgress: return .green
        case .skip: return .red
        case .upNext: return .orange
        case .none: return .gray.opacity(0.3)
        }
    }

    private var primaryText: String? {
        if let caption = frame.caption, !caption.isEmpty { return caption }
        return nil
    }

    private var secondaryText: String? {
        if let description = frame.description, !description.isEmpty { return description }
        return nil
    }

    @ViewBuilder
    private func statusOverlay(for status: FrameStatus) -> some View {
        switch status {
        case .done:
            GeometryReader { geometry in
                ZStack {
                    Path { path in
                        path.move(to: .zero)
                        path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                    }
                    .stroke(Color.red, lineWidth: 5)

                    Path { path in
                        path.move(to: CGPoint(x: geometry.size.width, y: 0))
                        path.addLine(to: CGPoint(x: 0, y: geometry.size.height))
                    }
                    .stroke(Color.red, lineWidth: 5)
                }
            }
            .aspectRatio(16/9, contentMode: .fit)
        case .skip:
            Color.red.opacity(0.3)
                .cornerRadius(12)
        case .inProgress, .upNext, .none:
            EmptyView()
        }
    }

    private var placeholder: some View {
        Image(systemName: "photo")
            .resizable()
            .scaledToFit()
            .foregroundColor(.gray.opacity(0.6))
            .padding(16)
    }
}

#Preview {
    let sample = Frame(id: "1", creativeId: "c1", description: "A sample description.", caption: "Sample Caption", status: FrameStatus.inProgress.rawValue, frameOrder: "1")
    FrameView(frame: sample) {}
}
