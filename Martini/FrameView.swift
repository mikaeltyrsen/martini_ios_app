import SwiftUI
import UniformTypeIdentifiers

struct FrameView: View {
    let frame: Frame
    @Binding var assetOrder: [FrameAssetKind]
    let onClose: () -> Void
    @State private var selectedStatus: FrameStatus
    @State private var assetStack: [FrameAssetItem]
    @State private var draggingAsset: FrameAssetItem?

    init(frame: Frame, assetOrder: Binding<[FrameAssetKind]>, onClose: @escaping () -> Void) {
        self.frame = frame
        _assetOrder = assetOrder
        self.onClose = onClose
        _selectedStatus = State(initialValue: frame.statusEnum)
        _assetStack = State(initialValue: FrameView.orderedAssets(for: frame, order: assetOrder.wrappedValue))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        if !assetStack.isEmpty {
                            assetStackView
                        }

                        FrameLayout(
                            frame: frame,
                            primaryAsset: primaryAsset,
                            title: primaryText,
                            subtitle: secondaryText,
                            cornerRadius: 12
                        )
                    }
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
            .onChange(of: assetOrder) { newOrder in
                assetStack = FrameView.orderedAssets(for: frame, order: newOrder)
            }
            .onChange(of: assetStack) { newStack in
                assetOrder = newStack.map(\.kind)
            }
        }
    }

    private var primaryAsset: FrameAssetItem? { assetStack.first }

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

    private var assetStackView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Assets")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: -30) {
                    ForEach(assetStack) { asset in
                        AssetCard(
                            asset: asset,
                            isPrimary: asset == primaryAsset,
                            onPromote: { promote(asset) }
                        )
                        .zIndex(Double(assetStack.count - (assetStack.firstIndex(of: asset) ?? 0)))
                        .onDrag {
                            draggingAsset = asset
                            return NSItemProvider(object: NSString(string: asset.kind.rawValue))
                        }
                        .onDrop(
                            of: [UTType.plainText],
                            delegate: AssetDropDelegate(
                                item: asset,
                                assets: $assetStack,
                                draggingAsset: $draggingAsset
                            )
                        )
                    }
                }
                .padding(.vertical, 4)
            }

            Text("Drag to reorder or tap to set the default asset shown on top.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func promote(_ asset: FrameAssetItem) {
        guard let index = assetStack.firstIndex(of: asset) else { return }
        withAnimation(.spring(response: 0.3)) {
            var updated = assetStack
            updated.remove(at: index)
            updated.insert(asset, at: 0)
            assetStack = updated
        }
    }

    private static func orderedAssets(for frame: Frame, order: [FrameAssetKind]) -> [FrameAssetItem] {
        let available = frame.availableAssets
        let ordered = order.compactMap { kind in available.first(where: { $0.kind == kind }) }
        let remaining = available.filter { !ordered.contains($0) }
        return ordered + remaining
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

private struct AssetCard: View {
    let asset: FrameAssetItem
    let isPrimary: Bool
    let onPromote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThickMaterial)
                    .frame(width: 180, height: 110)
                    .overlay(
                        Group {
                            if let url = asset.url {
                                if asset.isVideo {
                                    LoopingVideoView(url: url)
                                } else {
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
                                }
                            } else {
                                placeholder
                            }
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: isPrimary ? 6 : 2, y: 4)

                Label(asset.label, systemImage: asset.iconName)
                    .font(.caption.bold())
                    .padding(8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(8)
            }

            Button(action: onPromote) {
                HStack(spacing: 6) {
                    Image(systemName: isPrimary ? "star.fill" : "arrow.up")
                    Text(isPrimary ? "Default" : "Move to Top")
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isPrimary ? Color.accentColor.opacity(0.12) : Color.gray.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 30)
    }

    private var placeholder: some View {
        ZStack {
            Color.gray.opacity(0.15)
            Image(systemName: "photo")
                .font(.system(size: 28))
                .foregroundColor(.gray)
        }
    }
}

private struct AssetDropDelegate: DropDelegate {
    let item: FrameAssetItem
    @Binding var assets: [FrameAssetItem]
    @Binding var draggingAsset: FrameAssetItem?

    func performDrop(info: DropInfo) -> Bool {
        draggingAsset = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggingAsset, draggingAsset != item,
              let fromIndex = assets.firstIndex(of: draggingAsset),
              let toIndex = assets.firstIndex(of: item) else { return }

        withAnimation(.spring(response: 0.25)) {
            assets.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
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

