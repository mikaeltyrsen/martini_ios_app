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
                    FrameLayout(
                        frame: frame,
                        title: primaryText,
                        subtitle: secondaryText,
                        cornerRadius: 12
                    )
                    .padding()
                }
            }
            .navigationTitle("Frame \(frame.frameNumber > 0 ? String(frame.frameNumber) : "")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Menu {
                        statusMenuButton(title: "Done", status: .done, systemImage: "checkmark.circle")
                        statusMenuButton(title: "Here", status: .inProgress, systemImage: "figure.wave")
                        statusMenuButton(title: "Next", status: .upNext, systemImage: "arrow.turn.up.right")
                        statusMenuButton(title: "Omit", status: .skip, systemImage: "minus.circle")
                        statusMenuButton(title: "Clear", status: .none, systemImage: "xmark.circle")
                    } label: {
                        Label(statusMenuLabel, systemImage: selectedStatus.systemImageName)
                    }

                    Spacer()

                    Button("Close") { onClose() }
                }
            }
            .tint(.accentColor)
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

    private var statusMenuLabel: String {
        "Status: \(selectedStatus.displayName)"
    }

    @ViewBuilder
    private func statusMenuButton(title: String, status: FrameStatus, systemImage: String) -> some View {
        let isSelected = (selectedStatus == status)

        Button {
            withAnimation(.spring(response: 0.2)) {
                selectedStatus = status
            }
        } label: {
            Label(title, systemImage: systemImage)
                .foregroundStyle(Color.primary)
        }
        .accessibilityLabel("Set status to \(title)")
        .disabled(isSelected)
    }
}

private extension FrameStatus {
    var displayName: String {
        switch self {
        case .done:
            return "Done"
        case .inProgress:
            return "Here"
        case .skip:
            return "Omit"
        case .upNext:
            return "Next"
        case .none:
            return "Clear"
        }
    }

    var systemImageName: String {
        switch self {
        case .done:
            return "checkmark.circle"
        case .inProgress:
            return "figure.wave"
        case .upNext:
            return "arrow.turn.up.right"
        case .skip:
            return "minus.circle"
        case .none:
            return "xmark.circle"
        }
    }
}

#Preview {
    let sample = Frame(
        id: "1",
        creativeId: "c1",
        description: "A sample description.",
        caption: "Sample Caption",
        status: FrameStatus.inProgress.rawValue,
        frameOrder: "1"
    )
    FrameView(frame: sample) {}
}
