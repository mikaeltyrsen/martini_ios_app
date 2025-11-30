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
        .onAppear(perform: synchronizeRealtimeConnection)
        .onChange(of: authService.isAuthenticated) { _ in
            synchronizeRealtimeConnection()
        }
        .onChange(of: authService.projectId) { _ in
            synchronizeRealtimeConnection()
        }
    }

    private func synchronizeRealtimeConnection() {
        realtimeService.updateConnection(
            projectId: authService.projectId,
            isAuthenticated: authService.isAuthenticated
        )
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
    @State private var showGridSizeSlider: Bool = false
    @State private var showSizeControls: Bool = false
    @State private var gridSizeStep: Int = 1 // 1..4, where 1 -> 4 columns, 4 -> 1 column
    
    enum ViewMode {
        case list
        case grid
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
        return frames.sorted { $0.frameNumber < $1.frameNumber }
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
                        
                        // Top-left overlay: size control with popup
                        ZStack(alignment: .topLeading) {
                            if showSizeControls {
                                VStack(spacing: 0) {
                                    VStack(spacing: 8) {
                                        Button(action: {
                                            withAnimation(.spring(response: 0.2)) {
                                                gridSizeStep = max(1, gridSizeStep - 1)
                                            }
                                        }) {
                                            Image(systemName: "minus")
                                                .font(.system(size: 16, weight: .bold))
                                                .padding(8)
                                        }
                                        .accessibilityLabel("Decrease Grid Size")

                                        Divider()
                                            .frame(width: 28)

                                        Button(action: {
                                            withAnimation(.spring(response: 0.2)) {
                                                gridSizeStep = min(4, gridSizeStep + 1)
                                            }
                                        }) {
                                            Image(systemName: "plus")
                                                .font(.system(size: 16, weight: .bold))
                                                .padding(8)
                                        }
                                        .accessibilityLabel("Increase Grid Size")
                                    }
                                    .padding(8)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                                    )

                                    Triangle()
                                        .fill(Color(uiColor: .systemBackground).opacity(0.7))
                                        .frame(width: 14, height: 8)
                                        .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
                                        .offset(x: 16)
                                }
                                .transition(.move(edge: .top).combined(with: .opacity))
                                .offset(x: 8, y: 44)
                                .zIndex(2)
                            }

                            Button(action: {
                                withAnimation(.spring(response: 0.3)) {
                                    showSizeControls.toggle()
                                }
                            }) {
                                Image(systemName: showSizeControls ? "xmark" : "rectangle.compress.vertical")
                                    .font(.system(size: 18, weight: .semibold))
                                    .padding(10)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .padding(.leading, 12)
                            .padding(.top, 8)
                            .accessibilityLabel(showSizeControls ? "Close Size Controls" : "Open Size Controls")
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        
                        // Tap-capturing overlay to dismiss size popup
                        if showSizeControls {
                            Color.black.opacity(0.001) // invisible but receives taps
                                .ignoresSafeArea()
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.25)) {
                                        showSizeControls = false
                                    }
                                }
                                .transition(.opacity)
                                .zIndex(1)
                        }
                    }
                }
            }
            .navigationTitle(authService.projectId ?? "Martini")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Logout") {
                        authService.logout()
                    }
                    .foregroundColor(.red)
                }
                
                
                // Bottom-left controls: overview toggle only
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Spacer()
                        Button(action: {
                            withAnimation {
                                if viewMode == .grid {
                                    viewMode = .list
                                } else {
                                    viewMode = .grid
                                    showGridSizeSlider = false
                                    showSizeControls = false
                                }
                            }
                        }) {
                            Image(systemName: viewMode == .grid ? "xmark" : "square.grid.2x2")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .accessibilityLabel(viewMode == .grid ? "Close Overview" : "Open Overview")
                    }
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
                FrameView(frame: frame) {
                    selectedFrame = nil
                }
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
        ScrollView {
            LazyVStack(spacing: 20, pinnedViews: [.sectionHeaders]) {
                ForEach(creativesToDisplay) { creative in
                    CreativeGridSection(creative: creative, frames: frames(for: creative), onFrameTap: { frameId in
                        selectedFrameId = frameId
                        if let found = authService.frames.first(where: { $0.id == frameId }) {
                            selectedFrame = found
                        }
                        withAnimation {
                            // Tap switches to Grid View (kept as-is)
                            viewMode = .list
                        }
                    }, columnCount: gridColumnCount, showDescriptions: viewMode == .list)
                }
            }
            .padding(.vertical)
            .padding(.bottom, 0)
        }
    }
}

// MARK: - Creative Grid Section

struct CreativeGridSection: View {
    let creative: Creative
    let frames: [Frame]
    let onFrameTap: (String) -> Void
    let columnCount: Int
    let showDescriptions: Bool
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    private var columns: [GridItem] {
        let count = max(1, columnCount)
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Creative header
            Text(creative.title)
                .font(.headline)
                .fontWeight(.bold)
                .padding(.horizontal)

            // Grid of frames
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(frames) { frame in
                    Button {
                        onFrameTap(frame.id)
                    } label: {
                        GridFrameCell(frame: frame, showDescription: showDescriptions)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Grid Frame Cell

struct GridFrameCell: View {
    let frame: Frame
    var showDescription: Bool = false
    
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(16/9, contentMode: .fit)
                    .overlay(
                        Group {
                            if let urlString = frame.boardThumb ?? frame.board, let url = URL(string: urlString) {
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
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                // Frame number
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

                // Status overlays (red X for done)
                gridStatusOverlay(for: frame.statusEnum)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(gridBorderColor, lineWidth: 2)
            )

            // Optional description under the image
            if showDescription {
                Text(descriptionText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    @ViewBuilder
    private func gridStatusOverlay(for status: FrameStatus) -> some View {
        switch status {
        case .done:
            GeometryReader { geometry in
                ZStack {
                    Path { path in
                        path.move(to: .zero)
                        path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                    }
                    .stroke(Color.red, lineWidth: 2)

                    Path { path in
                        path.move(to: CGPoint(x: geometry.size.width, y: 0))
                        path.addLine(to: CGPoint(x: 0, y: geometry.size.height))
                    }
                    .stroke(Color.red, lineWidth: 2)
                }
            }
            .aspectRatio(16/9, contentMode: .fit)
        case .skip:
            Color.red.opacity(0.3)
                .cornerRadius(4)
        case .inProgress, .upNext, .none:
            EmptyView()
        }
    }
    
    private var gridBorderColor: Color {
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

    private var frameNumberText: String {
        frame.frameNumber > 0 ? "\(frame.frameNumber)" : "--"
    }
    
    private var descriptionText: String {
        if let caption = frame.caption, !caption.isEmpty {
            return caption
        }
        if let description = frame.description, !description.isEmpty {
            return description
        }
        return ""
    }

    private var placeholder: some View {
        Image(systemName: "photo")
            .resizable()
            .scaledToFit()
            .foregroundColor(.gray.opacity(0.6))
            .padding(16)
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

    var body: some View {
        FrameLayout(
            frame: frame,
            title: frame.caption,
            subtitle: descriptionText
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

#Preview {
    ContentView()
        .environmentObject(AuthService())
}

