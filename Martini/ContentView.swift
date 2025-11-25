//
//  ContentView.swift
//  Martini
//
//  Created by Mikael Tyrsen on 11/15/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authService: AuthService
    
    var body: some View {
        Group {
            if authService.isAuthenticated {
                MainView()
            } else {
                LoginView()
            }
        }
    }
}

// MARK: - Main Authenticated View

struct MainView: View {
    @EnvironmentObject var authService: AuthService
    @State private var viewMode: ViewMode = .list
    @State private var showViewOptions = false
    @State private var selectedFrameId: String?
    
    enum ViewMode {
        case list
        case grid
    }
    
    // MARK: - Mock Data (for design purposes)
    private var mockCreatives: [Creative] {
        [
            Creative(
                id: "1",
                shootId: "test-123",
                title: "Opening Scene",
                order: 1,
                isArchived: 0,
                isLive: 1,
                totalFrames: 8,
                completedFrames: 3,
                remainingFrames: 5,
                primaryFrameId: "f1",
                frameFileName: nil,
                frameImage: nil,
                frameBoardType: nil,
                frameStatus: "in-progress",
                frameNumber: 1,
                image: nil
            ),
            Creative(
                id: "2",
                shootId: "test-123",
                title: "Product Showcase",
                order: 2,
                isArchived: 0,
                isLive: 1,
                totalFrames: 12,
                completedFrames: 8,
                remainingFrames: 4,
                primaryFrameId: "f2",
                frameFileName: nil,
                frameImage: nil,
                frameBoardType: nil,
                frameStatus: "up-next",
                frameNumber: 9,
                image: nil
            ),
            Creative(
                id: "3",
                shootId: "test-123",
                title: "Closing Credits",
                order: 3,
                isArchived: 0,
                isLive: 1,
                totalFrames: 5,
                completedFrames: 5,
                remainingFrames: 0,
                primaryFrameId: "f3",
                frameFileName: nil,
                frameImage: nil,
                frameBoardType: nil,
                frameStatus: "done",
                frameNumber: 1,
                image: nil
            )
        ]
    }
    
    // Use mock data for now (set to true to see design)
    private let useMockData = true
    
    private var creativesToDisplay: [Creative] {
        useMockData ? mockCreatives : authService.creatives
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
                        if viewMode == .list {
                            creativesListView
                        } else {
                            gridView
                        }
                        
                        // Floating toolbar
                        floatingToolbar
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
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
            }
        }
    }
    
    private var creativesListView: some View {
        ScrollView {
            LazyVStack(spacing: 24, pinnedViews: [.sectionHeaders]) {
                ForEach(creativesToDisplay) { creative in
                    CreativeSection(creative: creative)
                        .id(creative.id)
                }
            }
            .padding(.vertical)
            .padding(.bottom, 80) // Space for floating toolbar
        }
    }
    
    private var gridView: some View {
        ScrollView {
            LazyVStack(spacing: 20, pinnedViews: [.sectionHeaders]) {
                ForEach(creativesToDisplay) { creative in
                    CreativeGridSection(creative: creative) { frameId in
                        // Switch to list view and scroll to frame
                        selectedFrameId = frameId
                        withAnimation {
                            viewMode = .list
                        }
                    }
                }
            }
            .padding(.vertical)
            .padding(.bottom, 80) // Space for floating toolbar
        }
    }
    
    private var floatingToolbar: some View {
        HStack(spacing: 20) {
            Spacer()
            
            // View mode button
            ZStack {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        showViewOptions.toggle()
                    }
                } label: {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.colorAccent)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
                }
                
                // Popup options
                if showViewOptions {
                    VStack(spacing: 12) {
                        viewModeButton(icon: "square.grid.3x3", label: "Grid", mode: .grid)
                        viewModeButton(icon: "list.bullet", label: "List", mode: .list)
                    }
                    .padding(12)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                    .offset(y: -120)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            
            Spacer()
        }
    }
    
    private func viewModeButton(icon: String, label: String, mode: ViewMode) -> some View {
        Button {
            withAnimation {
                viewMode = mode
                showViewOptions = false
            }
        } label: {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(label)
                    .font(.headline)
            }
            .foregroundColor(viewMode == mode ? .colorAccent : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Creative Grid Section

struct CreativeGridSection: View {
    let creative: Creative
    let onFrameTap: (String) -> Void
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    private var mockFrames: [MockFrame] {
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
            return MockFrame(id: "\(creative.id)-\(index)", number: index, status: status)
        }
    }
    
    private var columns: [GridItem] {
        let count = horizontalSizeClass == .compact ? 3 : 5
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
                ForEach(mockFrames) { frame in
                    Button {
                        onFrameTap(frame.id)
                    } label: {
                        GridFrameCell(frame: frame)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Grid Frame Cell

struct GridFrameCell: View {
    let frame: MockFrame
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.2))
                .aspectRatio(16/9, contentMode: .fit)
            
            // Frame number
            VStack {
                Spacer()
                Text("\(frame.number)")
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(4)
                    .padding(4)
            }
            
            // Status overlays
            if let status = frame.status {
                gridStatusOverlay(for: status)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(gridBorderColor, lineWidth: 2)
        )
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
        guard let status = frame.status else { return .clear }
        
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
            return .clear
        }
    }
}

// MARK: - Creative Section

struct CreativeSection: View {
    let creative: Creative
    
    // Mock frames - replace with actual frames later
    private var mockFrames: [MockFrame] {
        (1...creative.totalFrames).map { index in
            // Assign different statuses for demo purposes
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
            
            return MockFrame(id: "\(creative.id)-\(index)", number: index, status: status)
        }
    }
    
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
                ForEach(mockFrames) { frame in
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

// MARK: - Mock Frame Model

struct MockFrame: Identifiable {
    let id: String
    let number: Int
    let status: FrameStatus?
    
    init(id: String, number: Int, status: FrameStatus? = nil) {
        self.id = id
        self.number = number
        self.status = status
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
    let frame: MockFrame
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 16:9 placeholder image with status styling
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(16/9, contentMode: .fit)
                    .overlay(
                        VStack {
                            Image(systemName: "photo")
                                .font(.system(size: 40))
                                .foregroundColor(.gray.opacity(0.5))
                            Text("Frame #\(frame.number)")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    )
                
                // Status overlays
                if let status = frame.status {
                    statusOverlay(for: status)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
            
            // Lorem ipsum text
            Text("Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
    }
    
    @ViewBuilder
    private func statusOverlay(for status: FrameStatus) -> some View {
        switch status {
        case .done:
            // Red X lines from corner to corner
            GeometryReader { geometry in
                ZStack {
                    // Diagonal line from top-left to bottom-right
                    Path { path in
                        path.move(to: .zero)
                        path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                    }
                    .stroke(Color.red, lineWidth: 5)
                    
                    // Diagonal line from top-right to bottom-left  
                    Path { path in
                        path.move(to: CGPoint(x: geometry.size.width, y: 0))
                        path.addLine(to: CGPoint(x: 0, y: geometry.size.height))
                    }
                    .stroke(Color.red, lineWidth: 5)
                }
            }
            .aspectRatio(16/9, contentMode: .fit)
            
        case .skip:
            // Red transparent layer
            Color.red.opacity(0.3)
                .cornerRadius(8)
            
        case .inProgress, .upNext:
            EmptyView()
        
        case .none:
            EmptyView()
        }
    }
    
    private var borderColor: Color {
        guard let status = frame.status else { return .clear }
        
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
            return .clear
        }
    }
    
    private var borderWidth: CGFloat {
        frame.status != nil ? 3 : 0
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthService())
}
