import SwiftUI

@MainActor
struct FrameView: View {
    let frame: Frame
    @Binding var assetOrder: [FrameAssetKind]
    let onClose: () -> Void
    @State private var selectedStatus: FrameStatus
    @State private var assetStack: [FrameAssetItem]
    @State private var visibleAssetID: FrameAssetItem.ID?
    @State private var showingComments: Bool = false
    @State private var showingFiles: Bool = false
    @State private var descriptionExpanded: Bool = false
    @State private var descriptionScrollOffset: CGFloat = 0

    init(frame: Frame, assetOrder: Binding<[FrameAssetKind]>, onClose: @escaping () -> Void) {
        self.frame = frame
        _assetOrder = assetOrder
        self.onClose = onClose
        _selectedStatus = State(initialValue: frame.statusEnum)

        let orderValue: [FrameAssetKind] = assetOrder.wrappedValue
        let initialStack: [FrameAssetItem] = FrameView.orderedAssets(for: frame, order: orderValue)
        _assetStack = State(initialValue: initialStack)
        let firstID: FrameAssetItem.ID? = initialStack.first?.id
        _visibleAssetID = State(initialValue: firstID)
    }

    var body: some View {
        NavigationStack {
            contentView
                .navigationTitle("Frame \(frame.frameNumber > 0 ? String(frame.frameNumber) : "")")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    topToolbar
                    bottomToolbar
                }
        }
        .sheet(isPresented: $showingFiles) {
            FilesSheet(frameNumber: frame.frameNumber)
                .presentationDetents([.fraction(0.25), .medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: assetOrder) { (newOrder: [FrameAssetKind]) in
            let newStack: [FrameAssetItem] = FrameView.orderedAssets(for: frame, order: newOrder)
            assetStack = newStack
            if visibleAssetID == nil { visibleAssetID = newStack.first?.id }
        }
        .onChange(of: assetStack) { (newStack: [FrameAssetItem]) in
            assetOrder = newStack.map(\.kind)
            if visibleAssetID == nil, let first: FrameAssetItem.ID = newStack.first?.id {
                visibleAssetID = first
            }
        }
    }

    @ToolbarContentBuilder
    private var topToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Close") { onClose() }
        }
    }

    @ToolbarContentBuilder
    private var bottomToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            Button {
                showingFiles = true
            } label: {
                Label("Files", systemImage: "folder")
            }

            Spacer()

            
            Menu {
                statusMenuButton(title: "Done", status: .done, systemImage: "checkmark.circle")
                statusMenuButton(title: "Here", status: .inProgress, systemImage: "figure.wave")
                statusMenuButton(title: "Next", status: .upNext, systemImage: "arrow.turn.up.right")
                statusMenuButton(title: "Omit", status: .skip, systemImage: "minus.circle")
                statusMenuButton(title: "Clear", status: .none, systemImage: "xmark.circle")
            } label: {
                let statusColor = selectedStatus.labelColor
                HStack(spacing: 6) {
                    Image(systemName: selectedStatus.systemImageName)
                        .foregroundStyle(statusColor)
                    Text(selectedStatus.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(statusColor)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }

            Spacer()

            NavigationLink {
                CommentsPage(frameNumber: frame.frameNumber)
            } label: {
                Label("Comments", systemImage: "text.bubble")
            }
            
            
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if assetStack.isEmpty {
            AnyView(emptyState)
        } else {
            AnyView(mainContent)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.on.square")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No assets available")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mainContent: some View {
        GeometryReader { proxy in
            let collapsedHeight: CGFloat = proxy.size.height * 0.5
            let expandedHeight: CGFloat = proxy.size.height

            ZStack(alignment: .top) {
                boardsSection(height: collapsedHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                VStack {
                    Spacer()
                    descriptionOverlay(height: descriptionExpanded ? expandedHeight : collapsedHeight)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func boardsSection(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            StackedAssetScroller(
                frame: frame,
                assetStack: assetStack,
                visibleAssetID: $visibleAssetID,
                primaryText: primaryText
            )

            Spacer()

            boardCarouselTabs
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height, alignment: .top)
    }

    private var primaryText: String? {
        if let caption: String = frame.caption, !caption.isEmpty { return caption }
        return nil
    }

    private var secondaryText: String? {
        if let description: String = frame.description, !description.isEmpty { return description }
        return nil
    }

    @ViewBuilder
    private var descriptionSection: some View {
        if let secondaryText {
            let cleanText = plainTextFromHTML(secondaryText)
            VStack(alignment: .leading, spacing: 8) {
                Text("Description")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(cleanText)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.9))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Description")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("No description provided for this frame.")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func descriptionOverlay(height: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 44, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)

                descriptionSection
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: DescriptionScrollOffsetKey.self, value: proxy.frame(in: .named("descriptionScroll")).minY)
                }
            )
        }
        .coordinateSpace(name: "descriptionScroll")
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Color.black)
        .onPreferenceChange(DescriptionScrollOffsetKey.self) { offset in
            descriptionScrollOffset = offset
            handleDescriptionScroll(offset: offset)
        }
        .onTapGesture {
            guard !descriptionExpanded else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                descriptionExpanded = true
            }
        }
    }

    private func handleDescriptionScroll(offset: CGFloat) {
        let expandThreshold: CGFloat = -12
        let collapseThreshold: CGFloat = 18

        if !descriptionExpanded && offset < expandThreshold {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                descriptionExpanded = true
            }
        }

        if descriptionExpanded && offset > collapseThreshold {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                descriptionExpanded = false
            }
        }
    }

    private var statusMenuLabel: String {
        "Status: \(selectedStatus.displayName)"
    }

    @ViewBuilder
    private var boardCarouselTabs: some View {
        if assetStack.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(assetStack) { asset in
                        let isSelected: Bool = (asset.id == visibleAssetID)
                        Button {
                            visibleAssetID = asset.id
                        } label: {
                            Text(asset.label ?? asset.kind.displayName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(isSelected ? Color.white : Color.primary)
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .frame(minWidth: 80)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .scrollPosition(id: $visibleAssetID)
        } else if let asset = assetStack.first {
            HStack {
                Text(asset.label ?? asset.kind.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private func statusMenuButton(title: String, status: FrameStatus, systemImage: String) -> some View {
        let isSelected: Bool = (selectedStatus == status)

        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedStatus = status
            }
        } label: {
            Label(title, systemImage: systemImage)
                .foregroundStyle(Color.primary)
        }
        .accessibilityLabel("Set status to \(title)")
        .disabled(isSelected)
    }

    private static func orderedAssets(for frame: Frame, order: [FrameAssetKind]) -> [FrameAssetItem] {
        let available = frame.availableAssets
        var ordered: [FrameAssetItem] = []

        for kind in order {
            let matches = available.filter { $0.kind == kind && !ordered.contains($0) }
            ordered.append(contentsOf: matches)
        }

        for asset in available where !ordered.contains(asset) {
            ordered.append(asset)
        }

        return ordered
    }
}

private struct CommentsSheet: View {
    let frameNumber: Int
    
    @State private var newCommentText: String = ""
    @FocusState private var composeFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(0..<30), id: \.self) { index in
                        let idx: Int = index + 1
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Circle().fill(Color.blue.opacity(0.2)).frame(width: 28, height: 28)
                                Text("User \(idx)").font(.headline)
                                Spacer()
                                Text("2h ago").font(.caption).foregroundStyle(.secondary)
                            }
                            Text("This is a placeholder comment for frame \(frameNumber). It can wrap across multiple lines to demonstrate scrolling.")
                                .font(.body)
                            Divider()
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        // Input-like field that acts like a button
                        HStack {
                            Image(systemName: "text.bubble")
                                .foregroundStyle(.secondary)
                            TextField("Comment", text: $newCommentText)
                                .focused($composeFieldFocused)
                                .submitLabel(.send)
                                .onTapGesture { composeFieldFocused = true }
                                .onSubmit(sendComment)
                                .foregroundStyle(.primary)
                        }
                        .tint(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.clear, in: Capsule())
                        .overlay(
                            Capsule().stroke(Color.secondary.opacity(0.22), lineWidth: 1)
                        )

                        if !newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button(action: sendComment) {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
        }
    }
    
    private func sendComment() {
        let trimmed = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // TODO: Hook into your real comment-posting logic.
        withAnimation(.default) {
            newCommentText = ""
            composeFieldFocused = false
        }
    }

}

private struct CommentsPage: View {
    let frameNumber: Int
    @State private var newCommentText: String = ""
    @FocusState private var composeFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(0..<30), id: \.self) { index in
                    let idx: Int = index + 1
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Circle().fill(Color.blue.opacity(0.2)).frame(width: 28, height: 28)
                            Text("User \(idx)").font(.headline)
                            Spacer()
                            Text("2h ago").font(.caption).foregroundStyle(.secondary)
                        }
                        Text("This is a placeholder comment for frame \(frameNumber). It can wrap across multiple lines to demonstrate scrolling.")
                            .font(.body)
                        Divider()
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, 24)
        }
        .navigationTitle("Comments")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                HStack(spacing: 8) {
                    HStack {
                        Image(systemName: "text.bubble")
                            .foregroundStyle(.secondary)
                        TextField("Comment", text: $newCommentText)
                            .focused($composeFieldFocused)
                            .submitLabel(.send)
                            .onTapGesture { composeFieldFocused = true }
                            .onSubmit(sendComment)
                            .foregroundStyle(.primary)
                    }
                    .tint(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.clear, in: Capsule())
                    .overlay(
                        Capsule().stroke(Color.secondary.opacity(0.22), lineWidth: 1)
                    )

                    if !newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button(action: sendComment) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private func sendComment() {
        let trimmed = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // TODO: Hook into your real comment-posting logic.
        withAnimation(.default) {
            newCommentText = ""
            composeFieldFocused = false
        }
    }
}

private struct FilesSheet: View {
    let frameNumber: Int
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(0..<40), id: \.self) { index in
                        let idx: Int = index + 1
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.secondary.opacity(0.15))
                                .frame(width: 48, height: 48)
                                .overlay(Image(systemName: idx % 3 == 0 ? "doc.richtext" : "photo").foregroundStyle(.secondary))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(idx % 3 == 0 ? "Document_\(idx).pdf" : "Image_\(idx).jpg")
                                    .font(.headline)
                                Text("Placeholder file attached to frame \(frameNumber)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.down.circle")
                                .foregroundStyle(Color.accentColor)
                        }
                        Divider()
                    }
                }
                .padding()
            }
            .navigationTitle("Files")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private extension View {
    @ViewBuilder
    func applyHorizontalScrollTransition() -> some View {
        self.scrollTransition(.interactive, axis: .horizontal) { content, phase in
            let value: CGFloat = phase.value
            let isIdentity: Bool = phase.isIdentity
            let incomingNudge: CGFloat = max(0, value) * 24
            let stackedShift: CGFloat  = min(0, value) * 12
            let rawOffset: CGFloat = incomingNudge + stackedShift
            let offsetX: CGFloat = isIdentity ? 0 : rawOffset
            let scaleNegative: CGFloat = 0.5
            let scalePositive: CGFloat = 1.01
            let scaleIdentity: CGFloat = 1
            let scale: CGFloat = isIdentity ? scaleIdentity : (value < 0 ? scaleNegative : scalePositive)
            return content
                .offset(x: offsetX)
                .scaleEffect(scale)
        }
    }
}

private struct DescriptionScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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

    var labelColor: Color {
        switch self {
        case .done, .skip:
            return .red
        case .inProgress:
            return .green
        case .upNext:
            return .orange
        case .none:
            return .white
        }
    }
}

private struct StackedAssetScroller: View {
    let frame: Frame
    let assetStack: [FrameAssetItem]
    @Binding var visibleAssetID: FrameAssetItem.ID?
    let primaryText: String?

    var body: some View {
        GeometryReader { proxy in
            let cardWidth: CGFloat = proxy.size.width * 0.82
            let cardHeight: CGFloat = cardWidth * 1.15

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .center, spacing: 0) {
                    ForEach(assetStack) { asset in
                        AssetCardView(
                            frame: frame,
                            asset: asset,
                            cardWidth: cardWidth,
                            primaryText: primaryText
                        )
                        .id(asset.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $visibleAssetID)
            .contentMargins(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight)
        }
        .frame(minHeight: UIScreen.main.bounds.width * 0.82 * 1.15)
    }
}

private struct AssetCardView: View {
    let frame: Frame
    let asset: FrameAssetItem
    let cardWidth: CGFloat
    let primaryText: String?

    var body: some View {
        FrameLayout(
            frame: frame,
            primaryAsset: asset,
            title: primaryText,
            showStatusBadge: true,
            showFrameNumberOverlay: true,
            showTextBlock: false,
            cornerRadius: 16
        )
        .frame(width: cardWidth)
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .applyHorizontalScrollTransition()
        .shadow(radius: 10, x: 0, y: 10)
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


