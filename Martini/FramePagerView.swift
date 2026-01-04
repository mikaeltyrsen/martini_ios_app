import SwiftUI

struct FramePagerView: View {
    let frames: [Frame]
    let assetOrderBinding: (Frame) -> Binding<[FrameAssetKind]>
    let onClose: () -> Void
    let showsCloseButton: Bool
    let onStatusSelected: (Frame, FrameStatus) -> Void
    let onSelectionChanged: (Frame.ID) -> Void

    @State private var selection: Frame.ID
    @Environment(\.fullscreenMediaCoordinator) private var fullscreenCoordinator

    init(
        frames: [Frame],
        initialFrameID: Frame.ID,
        assetOrderBinding: @escaping (Frame) -> Binding<[FrameAssetKind]>,
        onClose: @escaping () -> Void,
        showsCloseButton: Bool = true,
        onStatusSelected: @escaping (Frame, FrameStatus) -> Void = { _, _ in },
        onSelectionChanged: @escaping (Frame.ID) -> Void = { _ in }
    ) {
        self.frames = frames
        self.assetOrderBinding = assetOrderBinding
        self.onClose = onClose
        self.showsCloseButton = showsCloseButton
        self.onStatusSelected = onStatusSelected
        self.onSelectionChanged = onSelectionChanged

        let resolvedInitialID = frames.first(where: { $0.id == initialFrameID })?.id
            ?? frames.first?.id
            ?? initialFrameID
        _selection = State(initialValue: resolvedInitialID)
    }

    var body: some View {
        Group {
            if frames.isEmpty {
                ContentUnavailableView("No Frames", systemImage: "film")
            } else {
                TabView(selection: $selection) {
                    ForEach(Array(frames.enumerated()), id: \.element.id) { index, frame in
                        FrameView(
                            frame: frame,
                            assetOrder: assetOrderBinding(frame),
                            onClose: onClose,
                            showsCloseButton: showsCloseButton,
                            hasPreviousFrame: index > 0,
                            hasNextFrame: index + 1 < frames.count,
                            showsTopToolbar: false,
                            activeFrameID: selection,
                            onNavigate: { direction in
                                switch direction {
                                case .previous:
                                    guard index > 0 else { return }
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        selection = frames[index - 1].id
                                    }
                                case .next:
                                    guard index + 1 < frames.count else { return }
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        selection = frames[index + 1].id
                                    }
                                }
                            },
                            onStatusSelected: onStatusSelected
                        )
                        .tag(frame.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .toolbar {
                    topToolbar
                }
                .onChange(of: selection) { newValue in
                    onSelectionChanged(newValue)
                }
            }
        }
        .fullScreenCover(item: fullscreenConfigurationBinding) { configuration in
            NavigationStack {
                FullscreenMediaViewer(
                    isPresented: fullscreenPresentationBinding,
                    media: configuration.media,
                    config: configuration.config
                )
            }
        }
    }

    private var fullscreenConfigurationBinding: Binding<FullscreenMediaConfiguration?> {
        Binding(
            get: { fullscreenCoordinator?.configuration },
            set: { newValue in
                fullscreenCoordinator?.configuration = newValue
            }
        )
    }

    private var fullscreenPresentationBinding: Binding<Bool> {
        Binding(
            get: { fullscreenCoordinator?.configuration != nil },
            set: { isPresented in
                if !isPresented {
                    fullscreenCoordinator?.configuration = nil
                }
            }
        )
    }

    private var selectedIndex: Int? {
        frames.firstIndex { $0.id == selection }
    }

    private func navigate(_ direction: FrameNavigationDirection) {
        guard let index = selectedIndex else { return }
        switch direction {
        case .previous:
            guard index > 0 else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                selection = frames[index - 1].id
            }
        case .next:
            guard index + 1 < frames.count else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                selection = frames[index + 1].id
            }
        }
    }

    @ToolbarContentBuilder
    private var topToolbar: some ToolbarContent {
        if showsCloseButton {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Close")
            }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                navigate(.previous)
            } label: {
                Image(systemName: "arrow.left")
            }
            .accessibilityLabel("Previous frame")
            .disabled((selectedIndex ?? 0) == 0)

            Button {
                navigate(.next)
            } label: {
                Image(systemName: "arrow.right")
            }
            .accessibilityLabel("Next frame")
            .disabled((selectedIndex ?? frames.count - 1) >= frames.count - 1)
        }
    }
}
