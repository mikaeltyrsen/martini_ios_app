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
    @State private var frameSortMode: FrameSortMode = .story

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

                ToolbarItem(placement: .bottomBar) {
                    HStack(spacing: 12) {
                        Menu {
                            sortMenuButton(title: "Story Order", mode: .story)
                            sortMenuButton(title: "Shoot Order", mode: .shoot)
                        } label: {
                            Label(sortMenuLabel, systemImage: "arrow.up.arrow.down")
                        }

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
                            Label(viewMode == .grid ? "Close Overview" : "Open Overview", systemImage: viewMode == .grid ? "xmark" : "square.grid.2x2")
                                .labelStyle(.titleAndIcon)
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .accessibilityLabel(viewMode == .grid ? "Close Overview" : "Open Overview")
                    }
                    .padding(.horizontal)
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
        FrameLayout(
            frame: frame,
            title: frame.caption,
            subtitle: showDescription ? frame.description : nil,
            cornerRadius: 6
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

