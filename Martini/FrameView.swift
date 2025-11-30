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

    private var primaryText: String? {
        if let caption = frame.caption, !caption.isEmpty { return caption }
        return nil
    }

    private var secondaryText: String? {
        if let description = frame.description, !description.isEmpty { return description }
        return nil
    }

}

#Preview {
    let sample = Frame(id: "1", creativeId: "c1", description: "A sample description.", caption: "Sample Caption", status: FrameStatus.inProgress.rawValue, frameOrder: "1")
    FrameView(frame: sample) {}
}
