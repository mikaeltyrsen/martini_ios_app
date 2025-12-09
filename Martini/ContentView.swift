//
//  ContentView.swift
//  Martini
//
//  Created by Mikael Tyrsen on 11/15/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var realtimeService: RealtimeService
    
    var body: some View {
        Group {
            if authService.isAuthenticated {
                MainView()
            } else {
                LoginView()
            }
        }
        .onAppear(perform: synchronizeAppState)
        .onChange(of: authService.isAuthenticated) { _ in
            synchronizeAppState()
        }
        .onChange(of: authService.projectId) { _ in
            synchronizeRealtimeConnection()
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
    }

    private func synchronizeRealtimeConnection() {
        realtimeService.updateConnection(
            projectId: authService.projectId,
            isAuthenticated: authService.isAuthenticated
        )
    }

    private func synchronizeAppState() {
        synchronizeRealtimeConnection()
    }

    private func handleIncomingURL(_ url: URL) {
        authService.handleDeepLink(url)
    }
}

// MARK: - Main Authenticated View

struct MainView: View {
    @EnvironmentObject var authService: AuthService
    @State private var viewMode: ViewMode = .list
    @State private var selectedFrameId: String?
    @State private var selectedFrame: Frame?
    @State private var dataError: String?
    @State private var hasLoadedFrames = false
    @State private var hasLoadedCreatives = false
    @AppStorage("gridSizeStep") private var gridSizeStep: Int = 1 // 1..4, where 1 -> 4 columns, 4 -> 1 column
    @State private var frameSortMode: FrameSortMode = .story
    @State private var isShowingSettings = false
    @State private var frameAssetOrders: [String: [FrameAssetKind]] = [:]
    @AppStorage("gridAssetPriority") private var gridAssetPriorityRawValue: String = FrameAssetKind.board.rawValue

    @AppStorage("showDescriptions") private var showDescriptions: Bool = true
    @AppStorage("showFullDescriptions") private var showFullDescriptions: Bool = false
    @AppStorage("gridFontStep") private var gridFontStep: Int = 3 // 1..5
    @State private var visibleFrameIds: Set<String> = []
    @State private var gridScrollProxy: ScrollViewProxy?
    @State private var currentHeaderTitle: String? = nil

    enum ViewMode {
        case list
        case grid
    }

    enum FrameSortMode {
        case story
        case shoot
    }
    
    // MARK: - Mock Data (for design purposes)
    private var mockCreatives: [Creative] {
        [
//            Creative(
//                id: "1",
//                shootId: "test-123",
//                title: "Opening Scene",
//                order: 1,
//                isArchived: 0,
//                isLive: 1,
//                totalFrames: 8,
//                completedFrames: 3,
//                remainingFrames: 5,
//                primaryFrameId: "f1",
//                frameFileName: nil,
//                frameImage: nil,
//                frameBoardType: nil,
//                frameStatus: "in-progress",
//                frameNumber: 1,
//                image: nil
//            ),
//            Creative(
//                id: "2",
//                shootId: "test-123",
//                title: "Product Showcase",
//                order: 2,
//                isArchived: 0,
//                isLive: 1,
//                totalFrames: 12,
//                completedFrames: 8,
//                remainingFrames: 4,
//                primaryFrameId: "f2",
//                frameFileName: nil,
//                frameImage: nil,
//                frameBoardType: nil,
//                frameStatus: "up-next",
//                frameNumber: 9,
//                image: nil
//            ),
//            Creative(
//                id: "3",
//                shootId: "test-123",
//                title: "Closing Credits",
//                order: 3,
//                isArchived: 0,
//                isLive: 1,
//                totalFrames: 5,
//                completedFrames: 5,
//                remainingFrames: 0,
//                primaryFrameId: "f3",
//                frameFileName: nil,
//                frameImage: nil,
//                frameBoardType: nil,
//                frameStatus: "done",
//                frameNumber: 1,
//                image: nil
//            )
        ]
    }
    
    // Use mock data for now (set to true to see design)
    private let useMockData = false

    private var creativesToDisplay: [Creative] {
        useMockData ? mockCreatives : authService.creatives
    }

    private var projectDisplayTitle: String {
        if let title = authService.projectTitle, !title.isEmpty {
            return title
        }
        return authService.projectId ?? "Martini"
    }

    private var overallCompletedFrames: Int {
        creativesToDisplay.reduce(0) { $0 + $1.completedFrames }
    }

    private var overallTotalFrames: Int {
        creativesToDisplay.reduce(0) { $0 + $1.totalFrames }
    }

    private var gridAssetPriority: FrameAssetKind {
        get { FrameAssetKind(rawValue: gridAssetPriorityRawValue) ?? .board }
        set { gridAssetPriorityRawValue = newValue.rawValue }
    }

    private var gridAssetPriorityBinding: Binding<FrameAssetKind> {
        Binding<FrameAssetKind>(
            get: { FrameAssetKind(rawValue: gridAssetPriorityRawValue) ?? .board },
            set: { gridAssetPriorityRawValue = $0.rawValue }
        )
    }

    private var effectiveShowDescriptions: Bool { viewMode == .grid ? false : showDescriptions }

    private var effectiveShowFullDescriptions: Bool { effectiveShowDescriptions && showFullDescriptions }

    private var gridColumnCount: Int {
        if viewMode == .grid { return 5 } // Overview fixed columns
        switch gridSizeStep { // Grid View adjustable
        case 1: return 4
        case 2: return 3
        case 3: return 2
        default: return 1
        }
    }

    private func frames(for creative: Creative) -> [Frame] {
        let frames = useMockData ? mockFrames(for: creative) : authService.frames.filter { $0.creativeId == creative.id }
        return frames.sorted { lhs, rhs in
            sortingTuple(for: lhs, mode: frameSortMode) < sortingTuple(for: rhs, mode: frameSortMode)
        }
    }

    private func mockFrames(for creative: Creative) -> [Frame] {
        (1...creative.totalFrames).map { index in
            let status: FrameStatus? = {
                if index <= creative.completedFrames {
                    return .done
                } else if index == creative.completedFrames + 1 {
                    return .inProgress
                } else if index == creative.completedFrames + 2 {
                    return .upNext
                } else if index == creative.totalFrames {
                    return .skip
                }
                return nil
            }()

            return Frame(
                id: "\(creative.id)-\(index)",
                creativeId: creative.id,
                description: "Placeholder description for frame #\(index)",
                caption: "Frame #\(index)",
                status: status?.rawValue,
                frameOrder: String(index)
            )
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if authService.isLoadingCreatives && !useMockData {
                    VStack {
                        ProgressView()
                        Text("Loading creatives...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top)
                    }
                } else if creativesToDisplay.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        
                        Text("No Creatives")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("No creatives found for this project.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    ZStack(alignment: .bottom) {
                        if viewMode == .list { // Grid View (adjustable grid)
                            gridView
                        } else { // Overview (fixed 5 columns)
                            gridView
                        }
                        
                        // Floating “Jump to In-Progress” button
                        if shouldShowInProgressShortcut {
                            Button(action: scrollToInProgressFrame) {
                                HStack(spacing: 8) {
                                    Image(systemName: "eye")
                                    Text("Jump to In-Progress")
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(.ultraThickMaterial, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .shadow(radius: 3, y: 2)
                            .padding(.bottom, 12)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
            }
            .navigationTitle(projectDisplayTitle)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 6) {
                        Text(projectDisplayTitle)
                            .font(.headline)
                            .fontWeight(.semibold)

                        if overallTotalFrames > 0 {
                            ProgressView(value: Double(overallCompletedFrames), total: Double(overallTotalFrames))
                                .progressViewStyle(.linear)
                                .frame(width: 180)
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Logout") {
                        authService.logout()
                    }
                    .foregroundColor(.red)
                }

                ToolbarItemGroup(placement: .bottomBar) {
                    
                    Button(action: {
                        withAnimation {
                            if viewMode == .grid {
                                viewMode = .list
                            } else {
                                viewMode = .grid
                            }
                        }
                    }) {
                        Label(viewMode == .grid ? "Close Overview" : "Open Overview", systemImage: viewMode == .grid ? "xmark" : "square.grid.2x2")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel(viewMode == .grid ? "Close Overview" : "Open Overview")
                    
                    Spacer()
                    
                    Button {
                        withAnimation(.spring(response: 0.25)) {
                            frameSortMode = (frameSortMode == .story) ? .shoot : .story
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "photo.stack")
                            Text(frameSortMode == .story ? "Story" : "Shoot")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }

                    Spacer()
                    
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("Settings", systemImage: "switch.2")
                    }
                    .accessibilityLabel("Open Settings")
                }
                

            }
            .task {
                await loadCreativesIfNeeded()
                await loadFramesIfNeeded()
            }
            .alert(
                "Data Load Error",
                isPresented: Binding(
                    get: { dataError != nil },
                    set: { newValue in
                        if !newValue {
                            dataError = nil
                        }
                    }
                )
            ) {
                Button("OK") {
                    dataError = nil
                }
            } message: {
                Text(dataError ?? "Unknown error")
            }
            .fullScreenCover(item: $selectedFrame) { frame in
                FrameView(frame: frame, assetOrder: assetOrderBinding(for: frame)) {
                    selectedFrame = nil
                }
                .interactiveDismissDisabled(false)
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView(
                    showDescriptions: $showDescriptions,
                    showFullDescriptions: $showFullDescriptions,
                    gridSizeStep: $gridSizeStep,
                    gridFontStep: $gridFontStep,
                    gridPriority: gridAssetPriorityBinding
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(false)
            }
        }
    }

    private func loadCreativesIfNeeded() async {
        guard !useMockData, !hasLoadedCreatives else { return }
        do {
            try await authService.fetchCreatives()
            hasLoadedCreatives = true
        } catch {
            dataError = error.localizedDescription
            print("❌ Failed to load creatives: \(error)")
        }
    }

    private var sortMenuLabel: String {
        switch frameSortMode {
        case .story:
            return "Sort: Story"
        case .shoot:
            return "Sort: Shoot"
        }
    }

    @ViewBuilder
    private func sortMenuButton(title: String, mode: FrameSortMode) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.25)) {
                frameSortMode = mode
            }
        }) {
            if frameSortMode == mode {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
        .accessibilityLabel("Sort by \(title.lowercased())")
    }

    private func loadFramesIfNeeded() async {
        guard !useMockData, !hasLoadedFrames else { return }
        do {
            try await authService.fetchFrames()
            hasLoadedFrames = true
        } catch {
            dataError = error.localizedDescription
            print("❌ Failed to load frames: \(error)")
        }
    }
    
    private var creativesListView: some View {
        ScrollView {
            LazyVStack(spacing: 24, pinnedViews: [.sectionHeaders]) {
                ForEach(creativesToDisplay) { creative in
                    CreativeSection(creative: creative, frames: frames(for: creative))
                        .id(creative.id)
                }
            }
            .padding(.vertical)
            .padding(.bottom, 0)
        }
    }
    
    private var gridView: some View {
        ScrollViewReader { proxy in
            GeometryReader { outerGeo in
                ZStack(alignment: .top) {
                    ScrollView {
                        LazyVStack(spacing: 20) {
                            ForEach(creativesToDisplay) { creative in
                                VStack(alignment: .leading, spacing: 12) {
                                    CreativeGridSection(
                                        creative: creative,
                                        frames: frames(for: creative),
                                        onFrameTap: { frameId in
                                            selectedFrameId = frameId
                                            if let found = authService.frames.first(where: { $0.id == frameId }) {
                                                selectedFrame = found
                                            }
                                            withAnimation {
                                                viewMode = .list
                                            }
                                        },
                                        columnCount: gridColumnCount,
                                        showDescriptions: effectiveShowDescriptions,
                                        showFullDescriptions: effectiveShowFullDescriptions,
                                        fontScale: fontScale,
                                        coordinateSpaceName: "gridScroll",
                                        viewportHeight: outerGeo.size.height,
                                        primaryAsset: { primaryAsset(for: $0) },
                                        onStatusSelected: { frame, status in
                                            updateFrameStatus(frame, to: status)
                                        }
                                    )
                                }
                                .id(creative.id)
                            }
                        }
                        .padding(.vertical)
                        .padding(.bottom, 0)
                    }
                    .coordinateSpace(name: "gridScroll")
                    .onAppear { gridScrollProxy = proxy }
                    .onPreferenceChange(SectionHeaderAnchorKey.self) { positions in
                        // Only show the sticky header once the section title has scrolled past the top
                        DispatchQueue.main.async {
                            let visible = positions
                                .filter { $0.value <= 0 }
                                .sorted(by: { $0.value > $1.value })
                                .first?.key
                            if let id = visible, let creative = creativesToDisplay.first(where: { $0.id == id }) {
                                currentHeaderTitle = creative.title
                            } else {
                                currentHeaderTitle = nil
                            }
                        }
                    }

                    if let title = currentHeaderTitle {
                        HStack {
                            Text(title)
                                .font(.headline)
                                .fontWeight(.bold)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(.thinMaterial)
                    }
                }
            }
        }
    }
    
    private var fontScale: CGFloat {
        switch gridFontStep {
        case 1: return 0.85
        case 2: return 1.0
        case 3: return 1.15
        case 4: return 1.3
        case 5: return 1.45
        default: return 1.0
        }
    }
}

private extension MainView {
    func sortingTuple(for frame: Frame, mode: FrameSortMode) -> (Int, Int) {
        let storyOrder = intValue(from: frame.frameOrder)
        let shootOrder = intValue(from: frame.frameShootOrder)

        switch mode {
        case .story:
            return (storyOrder ?? Int.max, shootOrder ?? Int.max)
        case .shoot:
            // Frames without a shoot order are sent to the end
            return (shootOrder ?? Int.max, storyOrder ?? Int.max)
        }
    }

    func intValue(from value: String?) -> Int? {
        guard let value, let intValue = Int(value) else { return nil }
        return intValue
    }

    var inProgressFrame: Frame? {
        authService.frames.first { $0.statusEnum == .inProgress }
    }

    var shouldShowInProgressShortcut: Bool {
        guard let id = inProgressFrame?.id else { return false }
        return !visibleFrameIds.contains(id)
    }

    func scrollToInProgressFrame() {
        guard let id = inProgressFrame?.id, let proxy = gridScrollProxy else { return }
        withAnimation {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    func assetOrder(for frame: Frame) -> [FrameAssetKind] {
        let availableKinds = frame.availableAssets.map(\.kind)
        var stored = frameAssetOrders[frame.id]?.filter { availableKinds.contains($0) } ?? []

        for kind in availableKinds where !stored.contains(kind) {
            stored.append(kind)
        }

        frameAssetOrders[frame.id] = stored
        return stored
    }

    func primaryAsset(for frame: Frame) -> FrameAssetItem? {
        let available = frame.availableAssets
        let order = prioritizedAssetOrder(for: frame)

        for kind in order {
            if let match = available.first(where: { $0.kind == kind }) {
                return match
            }
        }

        return available.first
    }

    func promoteAsset(_ kind: FrameAssetKind, for frame: Frame) {
        var order = assetOrder(for: frame)
        if let index = order.firstIndex(of: kind) {
            order.remove(at: index)
        }
        order.insert(kind, at: 0)
        frameAssetOrders[frame.id] = order
    }

    func assetOrderBinding(for frame: Frame) -> Binding<[FrameAssetKind]> {
        Binding(
            get: { assetOrder(for: frame) },
            set: { frameAssetOrders[frame.id] = $0 }
        )
    }

    private func prioritizedAssetOrder(for frame: Frame) -> [FrameAssetKind] {
        let baseOrder = assetOrder(for: frame)

        switch gridAssetPriority {
        case .board:
            return baseOrder
        case .photoboard:
            return prioritize(order: baseOrder, primary: .photoboard)
        case .preview:
            return prioritize(order: baseOrder, primary: .preview)
        }
    }

    private func prioritize(order: [FrameAssetKind], primary: FrameAssetKind) -> [FrameAssetKind] {
        var remaining = order
        var prioritized: [FrameAssetKind] = []

        if let index = remaining.firstIndex(of: primary) {
            prioritized.append(primary)
            remaining.remove(at: index)
        }

        if let index = remaining.firstIndex(of: .board) {
            prioritized.append(.board)
            remaining.remove(at: index)
        }

        prioritized.append(contentsOf: remaining)
        return prioritized
    }

    private func updateFrameStatus(_ frame: Frame, to status: FrameStatus) {
        authService.updateFrameStatus(id: frame.id, to: status)
    }
}

// MARK: - Creative Grid Section

struct CreativeGridSection: View {
    let creative: Creative
    let frames: [Frame]
    let onFrameTap: (String) -> Void
    let columnCount: Int
    let showDescriptions: Bool
    let showFullDescriptions: Bool
    let fontScale: CGFloat
    let coordinateSpaceName: String
    let viewportHeight: CGFloat
    let primaryAsset: (Frame) -> FrameAssetItem?
    let onStatusSelected: (Frame, FrameStatus) -> Void

    init(
        creative: Creative,
        frames: [Frame],
        onFrameTap: @escaping (String) -> Void,
        columnCount: Int,
        showDescriptions: Bool,
        showFullDescriptions: Bool,
        fontScale: CGFloat,
        coordinateSpaceName: String,
        viewportHeight: CGFloat,
        primaryAsset: @escaping (Frame) -> FrameAssetItem?,
        onStatusSelected: @escaping (Frame, FrameStatus) -> Void
    ) {
        self.creative = creative
        self.frames = frames
        self.onFrameTap = onFrameTap
        self.columnCount = columnCount
        self.showDescriptions = showDescriptions
        self.showFullDescriptions = showFullDescriptions
        self.fontScale = fontScale
        self.coordinateSpaceName = coordinateSpaceName
        self.viewportHeight = viewportHeight
        self.primaryAsset = primaryAsset
        self.onStatusSelected = onStatusSelected
    }

    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    private var columns: [GridItem] {
        let count = max(1, columnCount)
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(){
                TrackableHeader(id: creative.id, title: creative.title, coordSpace: coordinateSpaceName)
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: Double(creative.completedFrames), total: Double(max(creative.totalFrames, 1)))
                        .tint(.accentColor)
                        .accessibilityLabel("\(creative.completedFrames) of \(creative.totalFrames) frames complete")
                    
                    HStack {
                        Text("\(creative.completedFrames) completed")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("\(creative.totalFrames) total")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
            }

            // Grid of frames
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(frames) { frame in
                    Button {
                        onFrameTap(frame.id)
                    } label: {
                        GridFrameCell(
                            frame: frame,
                            primaryAsset: primaryAsset(frame),
                            showDescription: showDescriptions,
                            showFullDescription: showFullDescriptions,
                            fontScale: fontScale,
                            coordinateSpaceName: coordinateSpaceName,
                            viewportHeight: viewportHeight,
                            onStatusSelected: { status in
                                onStatusSelected(frame, status)
                            }
                        )
                    }
                    .id(frame.id)
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Grid Frame Cell

struct GridFrameCell: View {
    let frame: Frame
    var primaryAsset: FrameAssetItem?
    var showDescription: Bool = false
    var showFullDescription: Bool = false
    var fontScale: CGFloat
    let coordinateSpaceName: String
    let viewportHeight: CGFloat
    var onStatusSelected: (FrameStatus) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FrameLayout(
                frame: frame,
                primaryAsset: primaryAsset,
                title: frame.caption,
                cornerRadius: 6
            )
            .contextMenu {
                statusMenu
            }
            if showDescription, let desc = frame.description, !desc.isEmpty {
                let clean = plainTextFromHTML(desc)
                Text(clean)
                    .font(.system(size: 12 * fontScale))
                    .foregroundColor(.secondary)
                    .lineLimit(showFullDescription ? nil : 3)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: VisibleFramePreferenceKey.self,
                    value: isVisible(geo.frame(in: .named(coordinateSpaceName))) ? [frame.id] : []
                )
            }
        )
    }

    private func isVisible(_ rect: CGRect) -> Bool {
        rect.maxY >= 0 && rect.minY <= viewportHeight
    }

    private var statusMenu: some View {
        ForEach([FrameStatus.done, .inProgress, .upNext, .skip, .none], id: \.self) { status in
            Button {
                onStatusSelected(status)
            } label: {
                Label(status.displayName, systemImage: status.systemImageName)
            }
        }
    }
}

private struct VisibleFramePreferenceKey: PreferenceKey {
    static var defaultValue: Set<String> = []

    static func reduce(value: inout Set<String>, nextValue: () -> Set<String>) {
        value.formUnion(nextValue())
    }
}

private struct SectionHeaderAnchorKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct TrackableHeader: View {
    let id: String
    let title: String
    let coordSpace: String
    var body: some View {
        Text(title)
            .font(.headline)
            .fontWeight(.bold)
            .padding(.horizontal)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: SectionHeaderAnchorKey.self,
                        value: [id: geo.frame(in: .named(coordSpace)).minY]
                    )
                }
            )
    }
}

// MARK: - Creative Section

struct CreativeSection: View {
    let creative: Creative
    let frames: [Frame]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Creative header
            VStack(alignment: .leading, spacing: 4) {
                Text(creative.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                
                HStack {
                    Text("\(creative.completedFrames)/\(creative.totalFrames) frames")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if let status = creative.frameStatus, !status.isEmpty {
                        Text(status.uppercased())
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(statusColor(for: status))
                            .cornerRadius(4)
                    }
                }
                .padding(.horizontal)
            }

            // Frames list
            VStack(spacing: 16) {
                ForEach(frames) { frame in
                    FrameRowView(frame: frame)
                }
            }
            .padding(.horizontal)
        }
    }
    
    private func statusColor(for status: String) -> Color {
        switch status.lowercased() {
        case "in-progress":
            return .blue
        case "up-next":
            return .orange
        case "done":
            return .green
        case "skip":
            return .gray
        default:
            return .secondary
        }
    }
}

enum FrameStatus: String {
    case done = "done"
    case inProgress = "in-progress"
    case skip = "skip"
    case upNext = "up-next"
    case none = ""
}

// MARK: - Frame Row View

struct FrameRowView: View {
    let frame: Frame
    var primaryAsset: FrameAssetItem? = nil

    var body: some View {
        FrameLayout(
            frame: frame,
            primaryAsset: primaryAsset,
            title: frame.caption
        )
    }

    private var descriptionText: String {
        if let description = frame.description, !description.isEmpty {
            return description
        }

        return "No description available."
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct SettingsView: View {
    @Binding var showDescriptions: Bool
    @Binding var showFullDescriptions: Bool
    @Binding var gridSizeStep: Int // 1..4 (4->1 col)
    @Binding var gridFontStep: Int // 1..5
    @Binding var gridPriority: FrameAssetKind

    var body: some View {
        NavigationStack {
            Form {
                Section("Grid") {
                    Toggle("Show Descriptions", isOn: $showDescriptions)

                    Toggle("Show Full Descriptions", isOn: $showFullDescriptions)
                        .disabled(!showDescriptions)

                    Picker("Prioritize", selection: $gridPriority) {
                        Text("Boards").tag(FrameAssetKind.board)
                        Text("Photo").tag(FrameAssetKind.photoboard)
                        Text("Preview").tag(FrameAssetKind.preview)
                    }
                    .pickerStyle(.segmented)

                    // Grid size slider: 1->4 maps to 4/3/2/1 columns (already handled by gridColumnCount)
                    VStack(alignment: .leading) {
                        Text("Grid Size")
                        HStack {
                            Image(systemName: "square.grid.4x3.fill")
                            Spacer()
                            Slider(value: Binding(
                                get: { Double(gridSizeStep) },
                                set: { gridSizeStep = Int($0.rounded()) }
                            ), in: 1...4, step: 1)
                            Spacer()
                            Image(systemName: "rectangle.fill")
                        }
                    }

                    // Font size slider: 1..5 steps
                    VStack(alignment: .leading) {
                        Text("Font Size")
                        HStack {
                            Image(systemName: "textformat.size.smaller")
                            Spacer()
                            Slider(value: Binding(
                                get: { Double(gridFontStep) },
                                set: { gridFontStep = Int($0.rounded()) }
                            ), in: 1...5, step: 1)
                            Spacer()
                            Image(systemName: "textformat.size.larger")
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var gridSizeLabel: String {
        switch gridSizeStep {
        case 1: return "Small (4 cols)"
        case 2: return "Small+ (3 cols)"
        case 3: return "Medium (2 cols)"
        case 4: return "Large (1 col)"
        default: return "Custom"
        }
    }

    private var fontSizeLabel: String {
        switch gridFontStep {
        case 1: return "XS"
        case 2: return "S"
        case 3: return "M"
        case 4: return "L"
        case 5: return "XL"
        default: return "M"
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthService())
}

