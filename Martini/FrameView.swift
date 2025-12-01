import SwiftUI

struct FrameView: View {
    let frame: Frame
    @Binding var assetOrder: [FrameAssetKind]
    let onClose: () -> Void
    @State private var selectedStatus: FrameStatus
    @State private var assetStack: [FrameAssetItem]
    @State private var visibleAssetID: FrameAssetItem.ID?

    init(frame: Frame, assetOrder: Binding<[FrameAssetKind]>, onClose: @escaping () -> Void) {
        self.frame = frame
        _assetOrder = assetOrder
        self.onClose = onClose
        _selectedStatus = State(initialValue: frame.statusEnum)

        let initialStack = FrameView.orderedAssets(for: frame, order: assetOrder.wrappedValue)
        _assetStack = State(initialValue: initialStack)
        _visibleAssetID = State(initialValue: initialStack.first?.id)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if assetStack.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "square.on.square")
                            .font(.system(size: 40))
                            .foregroundStyle(.tertiary)
                        Text("No assets available")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    stackedAssetScroller
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
            .onChange(of: assetOrder) { newOrder in
                let newStack = FrameView.orderedAssets(for: frame, order: newOrder)
                assetStack = newStack
                visibleAssetID = visibleAssetID ?? newStack.first?.id
            }
            .onChange(of: assetStack) { newStack in
                assetOrder = newStack.map(\.kind)
                if visibleAssetID == nil, let first = newStack.first?.id {
                    visibleAssetID = first
                }
            }
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

    private var stackedAssetScroller: some View {
        GeometryReader { proxy in
            let cardWidth = proxy.size.width * 0.82

            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(assetStack) { asset in
                        FrameLayout(
                            frame: frame,
                            primaryAsset: asset,
                            title: primaryText,
                            subtitle: secondaryText,
                            cornerRadius: 16
                        )
                        .frame(width: cardWidth)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                        .scrollTransition(.interactive, axis: .horizontal) { view, phase in
                            let slideInOffset = max(0, phase.value) * 160
                            let stackedOffset = min(0, phase.value) * 28
                            let scale = phase.isIdentity ? 1 : (phase.value < 0 ? 0.94 : 1.02)

                            view
                                .offset(x: phase.isIdentity ? 0 : slideInOffset + stackedOffset)
                                .scaleEffect(scale)
                                .shadow(radius: phase.isIdentity ? 12 : 8, y: 10)
                        }
                        .id(asset.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $visibleAssetID)
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private static func orderedAssets(for frame: Frame, order: [FrameAssetKind]) -> [FrameAssetItem] {
        let available = frame.availableAssets
        let ordered = order.compactMap { kind in available.first(where: { $0.kind == kind }) }
        let remaining = available.filter { !ordered.contains($0) }
        return ordered + remaining
    }
}

extension FrameStatus {
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
//
//#Preview {
//    let sample = Frame(
//        id: "1",
//        creativeId: "c1",
//        board: "https://example.com/board.jpg",
//        frameOrder: "1",
//        photoboard: "https://example.com/photoboard.jpg",
//        preview: "https://example.com/preview.mp4",
//        previewThumb: "https://example.com/preview_thumb.jpg",
//        description: "A sample description.",
//        caption: "Sample Caption",
//        status: FrameStatus.inProgress.rawValue
//    )
//    FrameView(frame: sample, assetOrder: .constant([.board, .photoboard, .preview])) {}
//}

