//
//  ContentView.swift
//  Martini
//
//  Created by Mikael Tyrsen on 11/15/25.
//

import SwiftUI
import UIKit

private enum FilterStorageKeys {
    static let selectedTagIds = "filterSelectedTagIds"
    static let selectedCreativeIds = "filterSelectedCreativeIds"
}

struct ContentView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var realtimeService: RealtimeService
    @EnvironmentObject var connectionMonitor: ConnectionMonitor
    @EnvironmentObject var fullscreenCoordinator: FullscreenMediaCoordinator
    @EnvironmentObject var nearbySignInService: NearbySignInService
    
    var body: some View {
        Group {
            if authService.isAuthenticated {
                MainView()
            } else {
                LoginView()
            }
        }
        .onAppear {
            synchronizeAppState()
            updateNearbyHosting()
        }
        .onChange(of: authService.isAuthenticated) { isAuthenticated in
            synchronizeAppState()
            updateNearbyHosting()
            if !isAuthenticated {
                clearStoredFilters()
            }
        }
        .onChange(of: authService.projectId) { _ in
            synchronizeRealtimeConnection()
            updateNearbyHosting()
        }
        .onChange(of: authService.accessCode) { _ in
            updateNearbyHosting()
        }
        .onChange(of: authService.projectDetails?.activeSchedule?.id) { newId in
            authService.clearCachedSchedules(keeping: newId)
        }
        .onChange(of: connectionMonitor.status) { newStatus in
            guard authService.isAuthenticated else { return }
            if newStatus == .backOnline {
                if !authService.pendingFrameStatusUpdates.isEmpty {
                    connectionMonitor.holdBackOnlineDisplay()
                }
                authService.flushPendingFrameStatusUpdates()
            } else {
                authService.resetQueuedFrameSyncStatus()
            }
        }
        .onChange(of: authService.queuedFrameSyncStatus) { newStatus in
            guard authService.isAuthenticated, connectionMonitor.status == .backOnline else { return }
            if newStatus == .syncing {
                connectionMonitor.holdBackOnlineDisplay()
            }
            if newStatus == .success {
                connectionMonitor.dismissBackOnline(after: 3)
            }
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .fullScreenCover(item: fullscreenConfigurationBinding) { configuration in
            NavigationStack {
                FullscreenMediaViewer(
                    isPresented: fullscreenPresentationBinding,
                    media: configuration.media,
                    config: configuration.config,
                    metadataItem: configuration.metadataItem,
                    thumbnailURL: configuration.thumbnailURL,
                    markupConfiguration: configuration.markupConfiguration,
                    startsInMarkupMode: configuration.startsInMarkupMode
                )
            }
        }
        .sheet(item: $nearbySignInService.pendingRequest) { request in
            NearbySignInRequestSheet(request: request)
                .environmentObject(nearbySignInService)
                .interactiveDismissDisabled()
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
        connectionMonitor.updateConnection(isAuthenticated: authService.isAuthenticated)
    }

    private func updateNearbyHosting() {
        guard authService.isAuthenticated,
              let projectId = authService.projectId,
              let projectCode = authService.accessCode else {
            nearbySignInService.stopHosting()
            return
        }
        nearbySignInService.startHosting(projectId: projectId, projectCode: projectCode)
    }

    private func handleIncomingURL(_ url: URL) {
        authService.handleDeepLink(url)
    }

    private func clearStoredFilters() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: FilterStorageKeys.selectedTagIds)
        defaults.removeObject(forKey: FilterStorageKeys.selectedCreativeIds)
    }

    private var fullscreenConfigurationBinding: Binding<FullscreenMediaConfiguration?> {
        Binding(
            get: { fullscreenCoordinator.configuration },
            set: { fullscreenCoordinator.configuration = $0 }
        )
    }

    private var fullscreenPresentationBinding: Binding<Bool> {
        Binding(
            get: { fullscreenCoordinator.configuration != nil },
            set: { isPresented in
                if !isPresented {
                    fullscreenCoordinator.configuration = nil
                }
            }
        )
    }
}

// MARK: - Nearby Sign-In Sheet

struct NearbySignInRequestSheet: View {
    let request: NearbySignInRequest
    @EnvironmentObject private var nearbySignInService: NearbySignInService
    @EnvironmentObject private var authService: AuthService

    var body: some View {
        let projectTitle = authService.projectTitle ?? "this project"

        VStack(spacing: 24) {
            Spacer(minLength: 0)

            VStack(spacing: 24) {
                Text("Share Your Project")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                Image(systemName: "iphone.gen2.crop.circle")
                    .font(.system(size: 72))
                    .foregroundColor(.secondary)

                Text("\(request.displayName) would like to join your project. Would you want to sign them in to \(projectTitle)?")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)

            Button {
                nearbySignInService.approvePendingRequest()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.fill.checkmark")
                    Text("Sign Them In")
                }
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.martiniDefaultTextColor)
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.martiniDefaultColor)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .presentationDetents([.medium])
        .overlay(alignment: .topTrailing) {
            Button {
                nearbySignInService.denyPendingRequest()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .padding(10)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
        }
    }
}

// MARK: - Main Authenticated View

struct MainView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var connectionMonitor: ConnectionMonitor
    @EnvironmentObject var fullscreenCoordinator: FullscreenMediaCoordinator
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var selectedTab: MainTab = .boards
    @State private var lastNonSearchTab: MainTab = .boards
    @State private var shouldAnimateTabIcons = false
    @State private var viewMode: ViewMode = .list
    @State private var isSearchExpanded = false
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var selectedMoreTab: MoreTab = .files
    @State private var selectedFrameId: String?
    @State private var selectedFrame: Frame?
    @State private var dataError: String?
    @State private var showingNoConnectionModal = false
    @State private var hasShownOfflineModal = false
    @State private var hasLoadedFrames = false
    @State private var hasLoadedProjectDetails = false
    @State private var hasLoadedCreatives = false
    @AppStorage("gridSizeStep") private var gridSizeStep: Int = 1 // 1..4, portrait: 4->1 columns, landscape: 5->2 columns
    @State private var frameSortMode: FrameSortMode = .story
    @State private var frameAssetOrders: [String: [FrameAssetKind]] = [:]
    @AppStorage("gridAssetPriority") private var gridAssetPriorityRawValue: String = FrameAssetKind.board.rawValue
    @State private var isLoadingSchedule = false
    @State private var manuallySelectedScheduleId: String? = nil
    @State private var projectFiles: [Clip] = []
    @State private var isLoadingProjectFiles: Bool = false
    @State private var projectFilesError: String?

    @AppStorage("showDescriptions") private var showDescriptions: Bool = true
    @AppStorage("showFullDescriptions") private var showFullDescriptions: Bool = false
    @AppStorage("showGridTags") private var showGridTags: Bool = false
    @AppStorage("gridFontStep") private var gridFontStep: Int = 3 // 1..5
    @AppStorage("doneCrossLineWidth") private var doneCrossLineWidth: Double = 5.0
    @AppStorage("showDoneCrosses") private var showDoneCrosses: Bool = true
    @State private var visibleFrameIds: Set<String> = []
    @State private var isHereShortcutVisible = false
    @State private var hereShortcutIconName = "arrow.up"
    @State private var gridScrollProxy: ScrollViewProxy?
    @State private var currentCreativeId: String? = nil
    @State private var isScrolledToTop: Bool = true
    @State private var scheduleNavigationPath: [ScheduleRoute] = []
    @State private var isShowingFilters = false
    @State private var selectedCreativeIds: Set<String> = []
    @State private var selectedTagIds: Set<String> = []
    @State private var hasLoadedFilters = false
    @AppStorage(FilterStorageKeys.selectedTagIds) private var storedSelectedTagIds: Data = Data()
    @AppStorage(FilterStorageKeys.selectedCreativeIds) private var storedSelectedCreativeIds: Data = Data()
    @State private var gridMagnification: CGFloat = 1.0
    @State private var isGridPinching: Bool = false
    @State private var gridUpdatingFrameIds: Set<String> = []

    enum ViewMode {
        case list
        case grid
    }

    enum FrameSortMode {
        case story
        case shoot
    }

    enum MainTab: Hashable {
        case boards
        case schedule
        case more
        case settings
        case search
    }

    enum MoreTab: Hashable {
        case files
        case comments
    }

    enum ScheduleRoute: Hashable {
        case list(ProjectSchedule)
        case detail(ProjectSchedule, ProjectScheduleItem)
    }

    private static let scheduleDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
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

    private var allCreatives: [Creative] {
        useMockData ? mockCreatives : authService.creatives
    }

    private var creativesToDisplay: [Creative] {
        guard !selectedCreativeIds.isEmpty else { return allCreatives }
        return allCreatives.filter { selectedCreativeIds.contains($0.id) }
    }

    private var displayedCreativeIds: Set<String> {
        Set(creativesToDisplay.map(\.id))
    }

    private var activeSchedule: ProjectSchedule? {
        guard let schedule = authService.projectDetails?.activeSchedule else { return nil }
        return authService.cachedSchedule(for: schedule.id) ?? schedule
    }

    private var activeScheduleEntries: [ProjectScheduleItem] {
        activeSchedule?.schedules ?? []
    }

    private var activeScheduleTitle: String {
        activeSchedule?.name ?? "Schedule"
    }

    private var projectDisplayTitle: String {
        if let title = authService.projectTitle, !title.isEmpty {
            return title
        }
        return authService.projectId ?? "Martini"
    }

    private var overallProgress: ProgressCounts {
        let frames = authService.frames.filter { displayedCreativeIds.contains($0.creativeId) }
        let totalOverride = creativesToDisplay.reduce(0) { $0 + $1.totalFrames }
        return progressCounts(for: frames, totalOverride: totalOverride)
    }
    
    private var navigationProgress: ProgressCounts {
        guard frameSortMode == .story, !isScrolledToTop else { return overallProgress }
        guard
            let currentId = currentCreativeId ?? creativesToDisplay.first?.id,
            let creative = creativesToDisplay.first(where: { $0.id == currentId })
        else {
            return overallProgress
        }

        return creativeProgress(creative)
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

    private var effectiveShowGridTags: Bool { viewMode != .grid && showGridTags }

    private var shouldShowFrameTimeOverlay: Bool {
        !(viewMode == .grid && authService.isScheduleActive)
    }

    private var isLandscape: Bool {
        if let verticalSizeClass, verticalSizeClass == .compact {
            return true
        }

        if let horizontalSizeClass, let verticalSizeClass,
           horizontalSizeClass == .regular, verticalSizeClass == .regular {
            return UIScreen.main.bounds.width > UIScreen.main.bounds.height
        }

        return UIScreen.main.bounds.width > UIScreen.main.bounds.height
    }

    private var gridColumnCount: Int {
        let step = (viewMode == .grid) ? 0 : gridSizeStep
        return adjustableColumnCount(for: step)
    }

    private func adjustableColumnCount(for step: Int) -> Int {
        switch step { // Grid View adjustable
        case 0: return isLandscape ? 6 : 5
        case 1: return isLandscape ? 5 : 4
        case 2: return isLandscape ? 4 : 3
        case 3: return isLandscape ? 3 : 2
        default: return isLandscape ? 2 : 1
        }
    }

    private func creativeProgress(_ creative: Creative) -> ProgressCounts {
        let frames = authService.frames.filter { $0.creativeId == creative.id }
        return progressCounts(for: frames, totalOverride: creative.totalFrames)
    }

    private var gridSections: [GridSectionData] {
        switch frameSortMode {
        case .story:
            return creativesToDisplay.compactMap { creative in
                let frames = frames(for: creative)
                let progress = creativeProgress(creative)

                if isFilterActive && frames.isEmpty {
                    return nil
                }

                return GridSectionData(
                    id: creative.id,
                    title: creative.title,
                    frames: frames,
                    completedFrames: progress.completed,
                    totalFrames: progress.total,
                    showHeader: showCreativeHeaders
                )
            }
        case .shoot:
            let mergedFrames = creativesToDisplay.flatMap { frames(for: $0, mode: .shoot) }
            let sortedFrames = mergedFrames.sorted { lhs, rhs in
                sortingTuple(for: lhs, mode: .shoot) < sortingTuple(for: rhs, mode: .shoot)
            }

            return [GridSectionData(
                id: "shoot-order",
                title: "Shoot Order",
                frames: sortedFrames,
                completedFrames: nil,
                totalFrames: nil,
                showHeader: false
            )]
        }
    }

    private var displayedFramesInCurrentMode: [Frame] {
        gridSections.flatMap(\.frames)
    }

    private var shootOrderedFrames: [Frame] {
        creativesToDisplay
            .flatMap { frames(for: $0, mode: .shoot) }
            .sorted { lhs, rhs in
                sortingTuple(for: lhs, mode: .shoot) < sortingTuple(for: rhs, mode: .shoot)
            }
    }

    private func frames(for creative: Creative, mode: FrameSortMode? = nil) -> [Frame] {
        let sortMode = mode ?? frameSortMode
        var frames = useMockData ? mockFrames(for: creative) : authService.frames.filter { $0.creativeId == creative.id }

        guard selectedCreativeIds.isEmpty || selectedCreativeIds.contains(creative.id) else {
            return []
        }

        if !selectedTagIds.isEmpty {
            frames = frames.filter { frame in
                guard let tags = frame.tags else { return false }
                let identifiers = tags.map(tagIdentifier)
                return identifiers.contains(where: { selectedTagIds.contains($0) })
            }
        }

        switch sortMode {
        case .story:
            break // Always show every board in story order, even when a schedule exists
        case .shoot:
            frames = frames.filter { !$0.isHidden }
            if authService.isScheduleActive {
                frames = frames.filter { $0.hasScheduledTime }
            }
        }

        return frames.sorted { lhs, rhs in
            sortingTuple(for: lhs, mode: sortMode) < sortingTuple(for: rhs, mode: sortMode)
        }
    }

    private func mockFrames(for creative: Creative) -> [Frame] {
        (1...creative.totalFrames).map { index in
            let status: FrameStatus? = {
                if index <= creative.completedFrames {
                    return .done
                } else if index == creative.completedFrames + 1 {
                    return .here
                } else if index == creative.completedFrames + 2 {
                    return .next
                } else if index == creative.totalFrames {
                    return .omit
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
        TabView(selection: $selectedTab) {
            boardsTab
            scheduleTab
            moreTab
            settingsTab
            searchTab
        }
        .onAppear {
            shouldAnimateTabIcons = true
        }
        .onChange(of: selectedTab) { newValue in
            if newValue == .search {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSearchExpanded = true
                }
                isSearchFocused = true
                selectedTab = lastNonSearchTab
                return
            }

            lastNonSearchTab = newValue

            if isSearchExpanded {
                isSearchExpanded = false
                isSearchFocused = false
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSearchExpanded {
                searchField
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var boardsTab: some View {
        NavigationStack {
            mainContentWithNavigation
        }
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                storyShootAccessory
            }
        }
        .tabItem {
            Label {
                Text("Boards")
            } icon: {
                Image(systemName: "rectangle.grid.3x3.fill")
                    .symbolEffect(.drawOn.byLayer, options: .nonRepeating, isActive: shouldAnimateTabIcons)
                    .symbolEffect(.bounce, value: selectedTab == .boards)
            }
        }
        .tag(MainTab.boards)
    }

    private var scheduleTab: some View {
        NavigationStack(path: $scheduleNavigationPath) {
            scheduleRootView
                .navigationDestination(for: ScheduleRoute.self) { route in
                    switch route {
                    case .list(let schedule):
                        SchedulesView(schedule: schedule) { item in
                            scheduleNavigationPath.append(ScheduleRoute.detail(schedule, item))
                        }
                    case .detail(let schedule, let item):
                        ScheduleView(schedule: schedule, item: item) { selectedItem in
                            applyManualScheduleSelection(selectedItem, schedule: schedule)
                        }
                    }
                }
        }
        .task(id: activeSchedule?.id) {
            guard let schedule = activeSchedule else { return }
            await loadSchedule(schedule, openDetail: false)
        }
        .tabItem {
            Label {
                Text("Schedule")
            } icon: {
                Image(systemName: "calendar.day.timeline.left")
                    .symbolEffect(.drawOn.byLayer, options: .nonRepeating, isActive: shouldAnimateTabIcons)
                    .symbolEffect(.bounce, value: selectedTab == .schedule)
            }
        }
        .tag(MainTab.schedule)
    }

    private var moreTab: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("More", selection: $selectedMoreTab) {
                    Text("Files").tag(MoreTab.files)
                    Text("Comments").tag(MoreTab.comments)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                Divider()

                Group {
                    switch selectedMoreTab {
                    case .files:
                        FilesSheet(
                            title: "Files",
                            clips: $projectFiles,
                            isLoading: $isLoadingProjectFiles,
                            errorMessage: $projectFilesError,
                            onReload: { await loadProjectFiles(force: true) },
                            onMediaPreview: { clip in
                                openProjectFilePreview(clip)
                            },
                            showsNavigation: false
                        )
                    case .comments:
                        commentsPlaceholder
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tabItem {
            Label {
                Text("More")
            } icon: {
                Image(systemName: "ellipsis.circle")
                    .symbolEffect(.drawOn.byLayer, options: .nonRepeating, isActive: shouldAnimateTabIcons)
                    .symbolEffect(.bounce, value: selectedTab == .more)
            }
        }
        .tag(MainTab.more)
    }

    private var searchTab: some View {
        Color.clear
            .tabItem {
                Label {
                    Text("Search")
                } icon: {
                    Image(systemName: "magnifyingglass")
                        .symbolEffect(.drawOn.byLayer, options: .nonRepeating, isActive: shouldAnimateTabIcons)
                        .symbolEffect(.bounce, value: selectedTab == .search)
                }
            }
            .tag(MainTab.search)
    }

    private var commentsPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Comments")
                .font(.title2.weight(.semibold))
            Text("Comments will live here soon.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var settingsTab: some View {
        SettingsView(
            showDescriptions: $showDescriptions,
            showFullDescriptions: $showFullDescriptions,
            showGridTags: $showGridTags,
            gridSizeStep: $gridSizeStep,
            gridFontStep: $gridFontStep,
            gridPriority: gridAssetPriorityBinding,
            doneCrossLineWidth: $doneCrossLineWidth,
            showDoneCrosses: $showDoneCrosses
        )
        .tabItem {
            if horizontalSizeClass == .regular {
                Image(systemName: "switch.2")
                    .symbolEffect(.drawOn.byLayer, options: .nonRepeating, isActive: shouldAnimateTabIcons)
                    .symbolEffect(.bounce, value: selectedTab == .settings)
                    .accessibilityLabel("Settings")
            } else {
                Label {
                    Text("Settings")
                } icon: {
                    Image(systemName: "switch.2")
                        .symbolEffect(.drawOn.byLayer, options: .nonRepeating, isActive: shouldAnimateTabIcons)
                        .symbolEffect(.bounce, value: selectedTab == .settings)
                }
            }
        }
        .tag(MainTab.settings)
    }

    @ViewBuilder
    private var scheduleRootView: some View {
        if let schedule = activeSchedule {
            if let entries = schedule.schedules, !entries.isEmpty {
                SchedulesView(schedule: schedule) { item in
                    scheduleNavigationPath.append(ScheduleRoute.detail(schedule, item))
                }
            } else if isLoadingSchedule {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading schedule...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Schedule")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text("No schedule available")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Schedule")
                .navigationBarTitleDisplayMode(.inline)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("Schedule not active")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var mainContentWithNavigation: some View {
        mainContentWithStateUpdates
            .onChange(of: connectionMonitor.status) { newStatus in
                if newStatus == .online || newStatus == .backOnline {
                    hasShownOfflineModal = false
                }
            }
    }

    private var mainContentWithStateUpdates: some View {
        withRemoteUpdates(
            withFrameSorting(
                withFilterPersistence(
                    withSelectionSync(mainContentWithSheets)
                )
            )
        )
    }

    private func withSelectionSync<Content: View>(_ content: Content) -> some View {
        content
            .onAppear(perform: synchronizeCreativeSelection)
            .onAppear(perform: loadStoredFiltersIfNeeded)
            .onChange(of: creativesToDisplay.count) { _ in
                synchronizeCreativeSelection()
            }
            .onChange(of: selectedCreativeIds) { _ in
                synchronizeCreativeSelection()
            }
    }

    private func withFilterPersistence<Content: View>(_ content: Content) -> some View {
        content
            .onChange(of: selectedCreativeIds) { _ in
                persistFilters()
            }
            .onChange(of: selectedTagIds) { _ in
                persistFilters()
            }
    }

    private func withFrameSorting<Content: View>(_ content: Content) -> some View {
        content
            .onChange(of: frameSortMode) { _ in
                scrollToPriorityFrame()
            }
    }

    private func withRemoteUpdates<Content: View>(_ content: Content) -> some View {
        content
            .onChange(of: authService.frameUpdateEvent) { event in
                guard let event else { return }
                handleFrameUpdateEvent(event)
            }
            .onChange(of: authService.frames.map(\.id)) { _ in
                pruneFilterSelectionsIfNeeded()
            }
            .onChange(of: authService.creatives.map(\.id)) { _ in
                pruneFilterSelectionsIfNeeded()
            }
            .onChange(of: authService.scheduleUpdateEvent) { event in
                guard let event else { return }
                handleScheduleUpdateEvent(event)
            }
            .onChange(of: authService.projectFilesUpdateEvent) { event in
                guard event != nil else { return }
                Task {
                    await loadProjectFiles(force: true)
                }
            }
            .onChange(of: authService.projectId) { _ in
                resetProjectFiles()
                Task {
                    await loadProjectFiles(force: false)
                }
            }
    }

    private var mainContentWithSheets: some View {
        mainContentWithOverlays
            .fullScreenCover(isPresented: selectedFrameIsPresented) {
                framePagerSheet
            }
    }

    private var mainContentWithOverlays: some View {
        mainContentWithAlerts
            .overlay { noConnectionOverlay }
            .overlay(alignment: .leading) {
                filterSidebar
            }
    }

    private var mainContentWithAlerts: some View {
        mainContentWithTasks
            .alert(
                "Data Load Error",
                isPresented: dataErrorIsPresented
            ) {
                Button("OK") {
                    dataError = nil
                }
            } message: {
                Text(dataError ?? "Unknown error")
            }
    }

    private var mainContentWithTasks: some View {
        mainContentWithToolbar
            .task {
                await loadProjectDetailsIfNeeded()
                await loadCreativesIfNeeded()
                await loadFramesIfNeeded()
                await loadProjectFilesIfNeeded()
            }
    }

    private var mainContentWithToolbar: some View {
        mainContent
            //.navigationTitle(displayedNavigationTitle)
            .toolbar { toolbarContent }
            .navigationBarTitleDisplayMode(.inline)
    }

    private var dataErrorIsPresented: Binding<Bool> {
        Binding(
            get: { dataError != nil },
            set: { newValue in
                if !newValue {
                    dataError = nil
                }
            }
        )
    }

    private var selectedFrameIsPresented: Binding<Bool> {
        Binding(
            get: { selectedFrameId != nil },
            set: { isPresented in
                if !isPresented {
                    selectedFrameId = nil
                    selectedFrame = nil
                }
            }
        )
    }

    private var noConnectionOverlay: some View {
        MartiniAlertModal(
            isPresented: $showingNoConnectionModal,
            iconName: "wifi.exclamationmark",
            iconColor: .red,
            title: "No Connection",
            message: "Martini can’t reach the server at the moment. You can keep working—markings are saved locally.\nOnce connection is restored, we’ll automatically push your updates and sync across all devices.",
            actions: noConnectionActions
        )
    }

    private var noConnectionActions: [MartiniAlertAction] {
        [
            MartiniAlertAction(title: "CONTINUE OFFLINE", style: .primary) {
                showingNoConnectionModal = false
            }
        ]
    }

    private var framePagerSheet: some View {
        NavigationStack {
            let pagerFrames = displayedFramesInCurrentMode
            if let initialFrameId = selectedFrameId ?? selectedFrame?.id ?? pagerFrames.first?.id {
                FramePagerView(
                    frames: pagerFrames,
                    initialFrameID: initialFrameId,
                    assetOrderBinding: { assetOrderBinding(for: $0) },
                    onClose: {
                        selectedFrameId = nil
                        selectedFrame = nil
                    },
                    onStatusSelected: { updatedFrame, _ in
                        applyLocalStatusUpdate(updatedFrame)
                    },
                    onSelectionChanged: { frameId in
                        selectedFrameId = frameId
                        if let match = pagerFrames.first(where: { $0.id == frameId }) {
                            selectedFrame = match
                        }
                    }
                )
            }
        }
        .interactiveDismissDisabled(false)
    }

    private var mainContent: some View {
        Group {
            if shouldShowInitialLoadingState {
                loadingView
            } else if creativesToDisplay.isEmpty {
                emptyStateView
            } else {
                contentStack
            }
        }
    }

    private var shouldShowInitialLoadingState: Bool {
        guard !useMockData else { return false }
        guard creativesToDisplay.isEmpty else { return false }
        return authService.isLoadingProjectDetails || authService.isLoadingCreatives
    }

    private var loadingView: some View {
        SkeletonGridPlaceholder(columnCount: gridColumnCount)
    }

    private var emptyStateView: some View {
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
    }

    private var contentStack: some View {
        ZStack(alignment: .bottom) {
            gridView

            if isHereShortcutVisible {
                Button(action: scrollToHereFrame) {
                    HStack(spacing: 8) {
                        Image(systemName: hereShortcutIconName)
                        Text("Jump to Here")
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

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .principal) {
            if shouldAllowCreativeSelectionMenu {
                Menu {
                    creativeMenuContent
                } label: {
                    navigationTitleStack
                }
                .accessibilityLabel("Select creative")
            } else {
                navigationTitleStack
            }
        }

        ToolbarItem(placement: .navigationBarLeading) {
            filterButton
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search boards", text: $searchText)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .focused($isSearchFocused)
            Button {
                withAnimation(.easeInOut(duration: 0.12)) {
                    isSearchExpanded = false
                    isSearchFocused = false
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Close search")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThickMaterial, in: Capsule())
        .onAppear {
            isSearchFocused = true
        }
    }

    private var storyShootAccessory: some View {
        Picker("Sort order", selection: $frameSortMode) {
            Text("Story").tag(FrameSortMode.story)
            Text("Shoot").tag(FrameSortMode.shoot)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 240)
    }

    private func openProjectFilePreview(_ clip: Clip) {
        guard let url = clip.fileURL else { return }
        let media: MediaItem = clip.isVideo ? .videoURL(url) : .imageURL(url)
        fullscreenCoordinator.configuration = FullscreenMediaConfiguration(
            media: media,
            config: .default,
            metadataItem: nil,
            thumbnailURL: clip.thumbnailURL,
            markupConfiguration: nil,
            startsInMarkupMode: false
        )
    }

    @MainActor
    private func loadSchedule(
        _ schedule: ProjectSchedule,
        replaceExistingRoutes: Bool = false,
        openDetail: Bool = false
    ) async {
        if openDetail {
            showSchedule(schedule, replaceExistingRoutes: replaceExistingRoutes)
        } else if replaceExistingRoutes, navigationPathContainsScheduleRoute {
            if let selectedItem = resolvedScheduleItem(in: schedule) {
                scheduleNavigationPath = updatedNavigationPath(with: schedule, fallbackItem: selectedItem)
            }
        }

        isLoadingSchedule = true
        defer { isLoadingSchedule = false }

        if let cached = await authService.cachedScheduleAsync(for: schedule.id) {
            refreshScheduleNavigation(with: cached, openDetail: openDetail)
        }

        do {
            let latest = try await authService.fetchSchedule(for: schedule.id)
            refreshScheduleNavigation(with: latest, openDetail: openDetail)
        } catch {
            dataError = error.localizedDescription
            if let cached = authService.cachedSchedule(for: schedule.id) {
                refreshScheduleNavigation(with: cached, openDetail: openDetail)
            }
        }
    }

    private func refreshScheduleNavigation(with schedule: ProjectSchedule, openDetail: Bool) {
        if openDetail {
            showSchedule(schedule, replaceExistingRoutes: true)
        } else if navigationPathContainsScheduleRoute,
                  let selectedItem = resolvedScheduleItem(in: schedule) {
            scheduleNavigationPath = updatedNavigationPath(with: schedule, fallbackItem: selectedItem)
        }
    }

    private func showSchedule(_ schedule: ProjectSchedule, replaceExistingRoutes: Bool = false) {
        guard let selectedItem = resolvedScheduleItem(in: schedule) else { return }

        if replaceExistingRoutes, navigationPathContainsScheduleRoute {
            scheduleNavigationPath = updatedNavigationPath(with: schedule, fallbackItem: selectedItem)
            return
        }

        scheduleNavigationPath.append(ScheduleRoute.detail(schedule, selectedItem))
    }

    private var navigationPathContainsScheduleRoute: Bool { !scheduleNavigationPath.isEmpty }

    private var currentScheduleId: String? {
        for route in scheduleNavigationPath.reversed() {
            switch route {
            case .list(let schedule):
                return schedule.id
            case .detail(let schedule, _):
                return schedule.id
            }
        }

        return nil
    }

    private func updatedNavigationPath(with schedule: ProjectSchedule, fallbackItem: ProjectScheduleItem?) -> [ScheduleRoute] {
        var newPath: [ScheduleRoute] = []
        let fallbackItem = fallbackItem ?? resolvedScheduleItem(in: schedule)

        for route in scheduleNavigationPath {
            switch route {
            case .list:
                if let fallbackItem {
                    newPath.append(.detail(schedule, fallbackItem))
                }
            case .detail(_, let item):
                if let updatedItem = schedule.schedules?.first(where: { $0.listIdentifier == item.listIdentifier || $0.id == item.id || $0.title == item.title }) {
                    newPath.append(.detail(schedule, updatedItem))
                } else if let fallbackItem {
                    newPath.append(.detail(schedule, fallbackItem))
                }
            }
        }

        if newPath.isEmpty, let fallbackItem {
            newPath = [.detail(schedule, fallbackItem)]
        }

        return newPath
    }

    private func applyManualScheduleSelection(_ item: ProjectScheduleItem, schedule: ProjectSchedule) {
        manuallySelectedScheduleId = item.listIdentifier
        replaceScheduleRoute(schedule: schedule, item: item)
    }

    private func replaceScheduleRoute(schedule: ProjectSchedule, item: ProjectScheduleItem) {
        guard navigationPathContainsScheduleRoute else {
            scheduleNavigationPath = [.detail(schedule, item)]
            return
        }

        var updatedPath = scheduleNavigationPath
        if !updatedPath.isEmpty {
            updatedPath.removeLast()
        }
        updatedPath.append(.detail(schedule, item))
        scheduleNavigationPath = updatedPath
    }

    private func resolvedScheduleItem(in schedule: ProjectSchedule) -> ProjectScheduleItem? {
        guard let entries = schedule.schedules, !entries.isEmpty else { return nil }

        if let manualId = manuallySelectedScheduleId {
            if let match = entries.first(where: { $0.listIdentifier == manualId || $0.id == manualId }) {
                return match
            }
            manuallySelectedScheduleId = nil
        }

        if let matching = firstMatchingSchedule(in: entries, schedule: schedule) {
            return matching
        }

        if let future = closestFutureSchedule(in: entries, schedule: schedule) {
            return future
        }

        return entries.first
    }

    private func firstMatchingSchedule(in entries: [ProjectScheduleItem], schedule: ProjectSchedule) -> ProjectScheduleItem? {
        let now = Date()
        let calendar = Calendar.current

        for entry in entries {
            guard let date = scheduleDate(for: entry, in: schedule) else { continue }
            if calendar.isDate(date, inSameDayAs: now) {
                return entry
            }
        }

        return nil
    }

    private func closestFutureSchedule(in entries: [ProjectScheduleItem], schedule: ProjectSchedule) -> ProjectScheduleItem? {
        let now = Date()
        var closest: (item: ProjectScheduleItem, date: Date)?

        for entry in entries {
            guard let date = scheduleDate(for: entry, in: schedule), date > now else { continue }
            if let currentClosest = closest {
                if date < currentClosest.date {
                    closest = (entry, date)
                }
            } else {
                closest = (entry, date)
            }
        }

        return closest?.item
    }

    private func scheduleDate(for entry: ProjectScheduleItem, in schedule: ProjectSchedule) -> Date? {
        let dateString = entry.date ?? schedule.date
        guard let trimmed = dateString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return Self.scheduleDateFormatter.date(from: trimmed)
    }

    private func handleScheduleUpdateEvent(_ event: ScheduleUpdateEvent) {
        _ = event
        guard navigationPathContainsScheduleRoute else { return }

        guard let schedule = activeSchedule,
              let entries = schedule.schedules,
              !entries.isEmpty
        else {
            resetScheduleNavigation()
            return
        }

        if let currentScheduleId, currentScheduleId != schedule.id {
            scheduleNavigationPath = []
            Task {
                await loadSchedule(schedule, openDetail: false)
            }
            return
        }

        Task {
            await loadSchedule(schedule, replaceExistingRoutes: true, openDetail: false)
        }
    }

    private func resetScheduleNavigation() {
        scheduleNavigationPath = []
    }

    private func loadProjectDetailsIfNeeded() async {
        if hasLoadedProjectDetails || authService.projectDetails != nil {
            hasLoadedProjectDetails = true
            return
        }

        do {
            try await authService.fetchProjectDetails()
            hasLoadedProjectDetails = true
        } catch {
            dataError = error.localizedDescription
            print("❌ Failed to load project details: \(error)")
        }
    }

    private func loadCreativesIfNeeded() async {
        guard !useMockData else { return }

        if hasLoadedCreatives || !authService.creatives.isEmpty {
            hasLoadedCreatives = true
            return
        }

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
            withAnimation(.easeInOut(duration: 0.12)) {
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
        guard !useMockData else { return }

        if hasLoadedFrames || !authService.frames.isEmpty {
            hasLoadedFrames = true
            return
        }

        do {
            try await authService.fetchFrames()
            hasLoadedFrames = true
        } catch {
            dataError = error.localizedDescription
            print("❌ Failed to load frames: \(error)")
        }
    }

    private func loadProjectFilesIfNeeded() async {
        guard !useMockData else { return }
        guard authService.projectId != nil else { return }
        guard projectFiles.isEmpty else { return }

        await loadProjectFiles(force: false)
    }

    @MainActor
    private func loadProjectFiles(force: Bool) async {
        guard let projectId = authService.projectId else {
            projectFilesError = "Missing project ID"
            return
        }

        if !force && !projectFiles.isEmpty { return }

        isLoadingProjectFiles = true
        defer { isLoadingProjectFiles = false }
        do {
            let fetched = try await authService.fetchProjectFiles(projectId: projectId, onlyLive: true)
            projectFiles = fetched
            projectFilesError = nil
        } catch {
            projectFilesError = error.localizedDescription
        }
    }

    private func resetProjectFiles() {
        projectFiles = []
        projectFilesError = nil
    }
    
    private var showCreativeHeaders: Bool { frameSortMode == .story }

    private var creativesListView: some View {
        ScrollView {
            LazyVStack(spacing: 24, pinnedViews: [.sectionHeaders]) {
                ForEach(creativesToDisplay) { creative in
                    let creativeFrames = frames(for: creative)
                    CreativeSection(
                        creative: creative,
                        frames: creativeFrames,
                        showHeader: showCreativeHeaders,
                        progress: creativeProgress(creative)
                    )
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
                        LazyVStack(spacing: 50) {
                            ForEach(gridSections) { section in
                                VStack(alignment: .leading, spacing: 12) {
                                    CreativeGridSection(
                                        section: section,
                                        onFrameTap: { frameId in
                                            selectedFrameId = frameId
                                            if let found = authService.frames.first(where: { $0.id == frameId }) {
                                                selectedFrame = found
                                            }
                                            withAnimation(.easeInOut(duration: 0.12)) {
                                                viewMode = .list
                                            }
                                        },
                                        columnCount: gridColumnCount,
                                        forceThinCrosses: viewMode == .grid,
                                        showDescriptions: effectiveShowDescriptions,
                                        showFullDescriptions: effectiveShowFullDescriptions,
                                        showTags: effectiveShowGridTags,
                                        showFrameTimeOverlay: shouldShowFrameTimeOverlay,
                                        fontScale: fontScale,
                                        coordinateSpaceName: "gridScroll",
                                        viewportHeight: outerGeo.size.height,
                                        primaryAsset: { primaryAsset(for: $0) },
                                        onStatusSelected: { frame, status in
                                            updateFrameStatus(frame, to: status)
                                        },
                                        showSkeleton: shouldShowFrameSkeleton && section.frames.isEmpty,
                                        isPinching: isGridPinching,
                                        updatingFrameIds: gridUpdatingFrameIds
                                    )
                                }
                                .id(section.id)
                            }
                        }
                        .padding(.vertical)
                        .padding(.bottom, 0)
                    }
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                guard viewMode != .grid else { return }
                                isGridPinching = true
                                handleGridMagnificationChange(value)
                            }
                            .onEnded { _ in
                                guard viewMode != .grid else { return }
                                gridMagnification = 1.0
                                isGridPinching = false
                            }
                    )
                    .coordinateSpace(name: "gridScroll")
                    .onAppear { gridScrollProxy = proxy }
                    .onPreferenceChange(VisibleFramePreferenceKey.self) { ids in
                        // Defer state updates to avoid mutating view state during the render pass while scrolling
                        DispatchQueue.main.async {
                            if visibleFrameIds != ids {
                                visibleFrameIds = ids
                            }
                            updateHereShortcutState(using: ids)
                        }
                    }
                    .onChange(of: viewMode) { _ in
                        isGridPinching = false
                        if viewMode == .grid {
                            DispatchQueue.main.async {
                                scrollToGridTop()
                            }
                        }
                        updateHereShortcutState(using: visibleFrameIds)
                    }
                    .onChange(of: frameSortMode) { _ in
                        updateHereShortcutState(using: visibleFrameIds)
                    }
                    .onPreferenceChange(SectionHeaderAnchorKey.self) { positions in
                        // Track the nearest section header above the fold so the selector stays in sync
                        DispatchQueue.main.async {
                            let topOffset = positions.values.min() ?? .infinity
                            isScrolledToTop = topOffset > 0

                            guard frameSortMode == .story else { return }

                            let visibleId = positions
                                .filter { $0.value <= 0 }
                                .sorted(by: { $0.value > $1.value })
                                .first?.key

                            if let id = visibleId, gridSections.contains(where: { $0.id == id }) {
                                currentCreativeId = id
                            } else if currentCreativeId == nil {
                                synchronizeCreativeSelection()
                            }
                        }
                    }
                }
            }
        }
    }

    private var currentCreativeTitle: String {
        if let id = currentCreativeId, let creative = creativesToDisplay.first(where: { $0.id == id }) {
            return creative.title
        }
        return creativesToDisplay.first?.title ?? "Creatives"
    }

    private func selectCreative(_ id: String) {
        currentCreativeId = id
        scrollToCreative(withId: id)
    }

    private func handleGridMagnificationChange(_ value: CGFloat) {
        let delta = value / max(gridMagnification, 0.01)
        let stepThreshold: CGFloat = 0.37

        if delta > 1.0 + stepThreshold {
            adjustGridSize(increase: true)
            gridMagnification = value
        } else if delta < 1.0 - stepThreshold {
            adjustGridSize(increase: false)
            gridMagnification = value
        }
    }

    private func adjustGridSize(increase: Bool) {
        let newValue = gridSizeStep + (increase ? 1 : -1)
        gridSizeStep = min(max(newValue, 1), 4)
    }

    private func synchronizeCreativeSelection() {
        guard let firstId = creativesToDisplay.first?.id else {
            currentCreativeId = nil
            return
        }

        if let currentCreativeId, creativesToDisplay.contains(where: { $0.id == currentCreativeId }) {
            return
        }

        currentCreativeId = firstId
    }

    private func scrollToCreative(withId id: String) {
        guard let proxy = gridScrollProxy else { return }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            proxy.scrollTo(id, anchor: .top)
        }
    }

    private func scrollToGridTop() {
        guard let topId = gridSections.first?.id else { return }
        guard let proxy = gridScrollProxy else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(topId, anchor: .top)
        }
    }

    private var displayedNavigationTitle: String {
        isScrolledToTop ? projectDisplayTitle : currentCreativeTitle
    }

    @ViewBuilder
    private var creativeMenuContent: some View {
        if !creativesToDisplay.isEmpty {
            Section("Creatives") {
                ForEach(creativesToDisplay) { creative in
                    Button {
                        selectCreative(creative.id)
                    } label: {
                        if creative.id == (currentCreativeId ?? creativesToDisplay.first?.id) {
                            Label(creative.title, systemImage: "checkmark")
                        } else {
                            Text(creative.title)
                        }
                    }
                }
            }
        }
    }

    private var navigationTitleStack: some View {
        navigationTitleHeader
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(shouldAllowCreativeSelectionMenu ? .isButton : [])
    }

    private enum ConnectionBannerKind {
        case unstable
        case offline
        case backOnline
    }

    private var navigationTitleHeader: some View {
        ZStack {
            if let banner = connectionBanner {
                connectionBannerView(banner)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                VStack(spacing: 6) {
                    Text(displayedNavigationTitle)
                        .font(.headline)
                        .fontWeight(.semibold)

                    let progress = navigationProgress
                    if isProjectLoading {
                        HStack(spacing: 6) {
                            ProgressView()
                                .progressViewStyle(.circular)
                            Text("Loading project...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    } else if progress.total > 0 {
                        ProgressView(value: Double(progress.completed), total: Double(progress.total))
                            .progressViewStyle(.linear)
                            .tint(.martiniDefaultColor)
                            .frame(width: 180)
                            .animation(.timingCurve(0.2, 0.0, 0.0, 1.0, duration: 0.35), value: progress.percentage)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: connectionMonitor.status)
        .animation(.easeInOut(duration: 0.25), value: authService.queuedFrameSyncStatus)
    }

    private var connectionBanner: (text: String, color: Color, kind: ConnectionBannerKind, iconName: String)? {
        switch connectionMonitor.status {
        case .online:
            return nil
        case .unstable:
            return ("Unstable Connection", .orange, .unstable, "wifi.exclamationmark")
        case .offline:
            return ("No Connection", .red, .offline, "bolt.horizontal.fill")
        case .backOnline:
            return ("Back online", .green, .backOnline, "network")
        }
    }

    @ViewBuilder
    private func connectionBannerView(_ banner: (text: String, color: Color, kind: ConnectionBannerKind, iconName: String)) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: banner.iconName)
                Text(banner.text)
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(banner.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(banner.color.opacity(0.2), in: Capsule())
            connectionBannerStatusView(for: banner.kind)
        }
    }

    @ViewBuilder
    private func connectionBannerStatusView(for kind: ConnectionBannerKind) -> some View {
        switch kind {
        case .unstable:
            EmptyView()
        case .offline:
            HStack(spacing: 6) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.7)
                TimelineView(.animation) { timeline in
                    let shouldShowQueued = queuedFrameStatusCount > 0
                        && Int(timeline.date.timeIntervalSinceReferenceDate) % 4 >= 2
                    Text(shouldShowQueued ? queuedFrameStatusText : "Retrying")
                        .animation(.easeInOut(duration: 0.35), value: shouldShowQueued)
                }
            }
            .font(.footnote)
            .foregroundColor(.secondary)
        case .backOnline:
            if shouldShowQueuedSyncStatus {
                HStack(spacing: 6) {
                    if authService.queuedFrameSyncStatus == .success {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.7)
                    }
                    Text(authService.queuedFrameSyncStatus == .success ? "Syncing complete" : "Syncing queued frames")
                }
                .font(.footnote)
                .foregroundColor(.secondary)
            } else {
                Text("Connection restored")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var queuedFrameStatusCount: Int {
        authService.pendingFrameStatusUpdates.count
    }

    private var queuedFrameStatusText: String {
        "\(queuedFrameStatusCount) marked \(queuedFrameStatusCount == 1 ? "frame" : "frames") queued for sync"
    }

    private var shouldShowQueuedSyncStatus: Bool {
        queuedFrameStatusCount > 0 || authService.queuedFrameSyncStatus != .idle
    }

    private var shouldAllowCreativeSelectionMenu: Bool {
        frameSortMode == .story && !creativesToDisplay.isEmpty
    }

    private var isProjectLoading: Bool {
        let isFetching = authService.isLoadingProjectDetails
            || authService.isLoadingCreatives
            || authService.isLoadingFrames
        return isFetching && creativesToDisplay.isEmpty && authService.frames.isEmpty
    }

    private var shouldShowFrameSkeleton: Bool {
        guard !useMockData else { return false }
        return authService.isLoadingFrames && authService.frames.isEmpty
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

    var hereFrame: Frame? {
        displayedFramesInCurrentMode.first { $0.statusEnum == .here }
    }

    func updateHereShortcutState(using visibleIds: Set<String>) {
        guard let frame = hereFrame else {
            if isHereShortcutVisible {
                isHereShortcutVisible = false
            }
            return
        }

        let shouldShow = !visibleIds.contains(frame.id)
        if shouldShow != isHereShortcutVisible {
            isHereShortcutVisible = shouldShow
        }

        guard shouldShow else { return }

        let indexLookup = Dictionary(uniqueKeysWithValues: displayedFramesInCurrentMode.enumerated().map { ($0.element.id, $0.offset) })

        guard let targetIndex = indexLookup[frame.id] else { return }

        let visibleIndices = visibleIds.compactMap { indexLookup[$0] }
        guard let minVisible = visibleIndices.min(), let maxVisible = visibleIndices.max() else { return }

        let updatedIconName: String
        if targetIndex < minVisible {
            updatedIconName = "arrow.up"
        } else if targetIndex > maxVisible {
            updatedIconName = "arrow.down"
        } else {
            updatedIconName = "arrow.up"
        }

        if updatedIconName != hereShortcutIconName {
            hereShortcutIconName = updatedIconName
        }
    }

    func scrollToHereFrame() {
        guard let frame = hereFrame else { return }
        scrollToFrame(frame)
    }

    private func scrollToPriorityFrame() {
        guard let target = preferredFrameForCurrentMode() else { return }

        DispatchQueue.main.async {
            scrollToFrame(target)
        }
    }

    private func handleFrameUpdateEvent(_ event: FrameUpdateEvent) {
        guard shouldScrollToHereFrame(for: event) else { return }
        scrollFrameIntoGridIfAvailable(frameId: event.frameId)
    }

    private func shouldScrollToHereFrame(for event: FrameUpdateEvent) -> Bool {
        guard case .websocket(let eventName) = event.context,
              eventName == "frame-status-updated"
        else {
            return false
        }

        guard let frame = displayedFramesInCurrentMode.first(where: { $0.id == event.frameId }) else {
            return false
        }

        return frame.statusEnum == .here
    }

    private func scrollFrameIntoGridIfAvailable(frameId: String, anchor: UnitPoint = .center) {
        guard let frame = displayedFramesInCurrentMode.first(where: { $0.id == frameId }) else { return }
        scrollToFrame(frame, anchor: anchor)
    }

    private func preferredFrameForCurrentMode() -> Frame? {
        if let here = displayedFramesInCurrentMode.first(where: { $0.statusEnum == .here }) {
            return here
        }

        return lastCrossedFrameInShootOrder()
    }

    private func scrollToFrame(_ frame: Frame, anchor: UnitPoint = .center) {
        guard let proxy = gridScrollProxy else { return }

        if frameSortMode == .story {
            currentCreativeId = frame.creativeId
        }

        let shouldPrimeSection = frameSortMode == .story
            && !visibleFrameIds.contains(frame.id)
            && gridSections.contains(where: { $0.id == frame.creativeId })

        if shouldPrimeSection {
            withAnimation {
                proxy.scrollTo(frame.creativeId, anchor: .top)
            }
            DispatchQueue.main.async {
                withAnimation {
                    proxy.scrollTo(frame.id, anchor: anchor)
                }
            }
        } else {
            withAnimation {
                proxy.scrollTo(frame.id, anchor: anchor)
            }
        }
    }

    private func lastCrossedFrameInShootOrder() -> Frame? {
        shootOrderedFrames.last { frame in
            let status = frame.statusEnum
            return status == .done || status == .omit
        }
    }

    private func navigationContext(for frame: Frame) -> (previous: Frame?, next: Frame?) {
        let frames = displayedFramesInCurrentMode
        guard let index = frames.firstIndex(where: { $0.id == frame.id }) else { return (nil, nil) }

        let previous = index > 0 ? frames[index - 1] : nil
        let nextIndex = index + 1
        let next = nextIndex < frames.count ? frames[nextIndex] : nil

        return (previous, next)
    }

    func assetOrder(for frame: Frame) -> [FrameAssetKind] {
        let availableKinds = frame.availableAssets.map(\.kind)
        var stored = frameAssetOrders[frame.id]?.filter { availableKinds.contains($0) } ?? []

        for kind in availableKinds where !stored.contains(kind) {
            stored.append(kind)
        }

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
        Task {
            await MainActor.run {
                gridUpdatingFrameIds.insert(frame.id)
            }
            defer {
                Task { @MainActor in
                    gridUpdatingFrameIds.remove(frame.id)
                }
            }
            do {
                let updateResult = try await authService.updateFrameStatus(id: frame.id, to: status)
                if selectedFrame?.id == frame.id {
                    selectedFrame = updateResult.frame
                }
                if updateResult.wasQueued {
                    await MainActor.run {
                        guard !hasShownOfflineModal else { return }
                        hasShownOfflineModal = true
                        showingNoConnectionModal = true
                    }
                }
            } catch {
                await MainActor.run {
                    dataError = error.localizedDescription
                }
            }
        }
    }

    private func applyLocalStatusUpdate(_ updatedFrame: Frame) {
        if selectedFrame?.id == updatedFrame.id {
            selectedFrame = updatedFrame
        }
    }

    private var isFilterActive: Bool {
        !selectedTagIds.isEmpty || !selectedCreativeIds.isEmpty
    }

    private var availableTagGroups: [TagGroup] {
        let frames = useMockData ? [] : authService.frames
        let allTags = frames.compactMap { $0.tags }.flatMap { $0 }

        let grouped = Dictionary(grouping: allTags) { tag -> String in
            let group = tag.groupName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (group?.isEmpty == false ? group : nil) ?? "Other"
        }

        return grouped.map { key, tags in
            TagGroup(id: key, name: key, tags: Array(Set(tags)).sorted { $0.name.lowercased() < $1.name.lowercased() })
        }
        .sorted { lhs, rhs in
            if lhs.name == "Other" { return false }
            if rhs.name == "Other" { return true }
            return lhs.name.lowercased() < rhs.name.lowercased()
        }
    }

    private func tagIdentifier(_ tag: FrameTag) -> String {
        tag.id ?? tag.name.lowercased()
    }

    private func toggleTag(_ tag: FrameTag) {
        let identifier = tagIdentifier(tag)
        if selectedTagIds.contains(identifier) {
            selectedTagIds.remove(identifier)
        } else {
            selectedTagIds.insert(identifier)
        }
    }

    private func toggleCreative(_ creative: Creative) {
        if selectedCreativeIds.contains(creative.id) {
            selectedCreativeIds.remove(creative.id)
        } else {
            selectedCreativeIds.insert(creative.id)
        }
    }

    private func clearFilters() {
        selectedTagIds.removeAll()
        selectedCreativeIds.removeAll()
    }

    private func loadStoredFiltersIfNeeded() {
        guard !hasLoadedFilters else { return }
        selectedTagIds = decodeFilterSet(from: storedSelectedTagIds)
        selectedCreativeIds = decodeFilterSet(from: storedSelectedCreativeIds)
        hasLoadedFilters = true
        pruneFilterSelectionsIfNeeded()
    }

    private func persistFilters() {
        storedSelectedTagIds = encodeFilterSet(selectedTagIds)
        storedSelectedCreativeIds = encodeFilterSet(selectedCreativeIds)
    }

    private func pruneFilterSelectionsIfNeeded() {
        if hasLoadedFrames || !authService.frames.isEmpty {
            let availableTagIds = Set(availableTagGroups.flatMap { group in
                group.tags.map { tagIdentifier($0) }
            })
            if availableTagIds.isEmpty {
                selectedTagIds.removeAll()
            } else {
                selectedTagIds = selectedTagIds.intersection(availableTagIds)
            }
        }

        if hasLoadedCreatives || !authService.creatives.isEmpty {
            let availableCreativeIds = Set(allCreatives.map(\.id))
            if availableCreativeIds.isEmpty {
                selectedCreativeIds.removeAll()
            } else {
                selectedCreativeIds = selectedCreativeIds.intersection(availableCreativeIds)
            }
        }
    }

    private func decodeFilterSet(from data: Data) -> Set<String> {
        guard !data.isEmpty, let stored = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(stored)
    }

    private func encodeFilterSet(_ set: Set<String>) -> Data {
        (try? JSONEncoder().encode(Array(set))) ?? Data()
    }

    private var filterButton: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                isShowingFilters.toggle()
            }
        } label: {
            Label("Filters", systemImage: isFilterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 16, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isFilterActive ? Color.accentColor.opacity(0.15) : Color(.systemGray5))
                )
                .overlay(
                    Capsule()
                        .stroke(isFilterActive ? Color.accentColor : Color(.systemGray3), lineWidth: 1)
                )
                .foregroundColor(isFilterActive ? .accentColor : .primary)
        }
        .accessibilityLabel(isFilterActive ? "Filters active" : "Open filters")
    }

    @ViewBuilder
    private var filterSidebar: some View {
        if isShowingFilters {
            ZStack(alignment: .leading) {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                            isShowingFilters = false
                        }
                    }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Filters")
                            .font(.title3)
                            .fontWeight(.semibold)

                        Spacer()

                        if isFilterActive {
                            Button("Clear") {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    clearFilters()
                                }
                            }
                            .font(.system(size: 14, weight: .semibold))
                        }

//                        Button {
//                            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
//                                isShowingFilters = false
//                            }
//                        } label: {
//                            Image(systemName: "xmark")
//                                .font(.system(size: 14, weight: .bold))
//                                .padding(8)
//                                .background(Color(.systemGray5), in: Circle())
//                        }
                    }

                    Divider()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Creatives")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)

                                if allCreatives.isEmpty {
                                    Text("No creatives available")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                } else {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(allCreatives) { creative in
                                            CreativeFilterRow(
                                                creative: creative,
                                                isSelected: selectedCreativeIds.contains(creative.id),
                                                action: { toggleCreative(creative) }
                                            )
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 4)
                            Divider()

                            if availableTagGroups.isEmpty {
                                Text("No tags available")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(availableTagGroups) { group in
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(group.name)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.secondary)

                                        VStack(alignment: .leading, spacing: 8) {
                                            ForEach(group.tags) { tag in
                                                FilterToggleRow(
                                                    tag: tag,
                                                    isSelected: selectedTagIds.contains(tagIdentifier(tag)),
                                                    action: { toggleTag(tag) }
                                                )
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.bottom, 4)
                                    Divider()
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
                .frame(width: 320, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(.ultraThickMaterial)
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.88), value: isShowingFilters)
        }
    }
}

private struct TagGroup: Identifiable {
    let id: String
    let name: String
    let tags: [FrameTag]
}

private struct CreativeFilterRow: View {
    let creative: Creative
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .imageScale(.medium)

                Text(creative.title)
                    .font(.body)
                    .foregroundColor(.primary)

                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Creative: \(creative.title)")
    }
}

private struct FilterToggleRow: View {
    let tag: FrameTag
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .imageScale(.medium)

                Text(tag.name)
                    .font(.body)
                    .foregroundColor(.primary)

                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tag: \(tag.name)")
    }
}

struct GridSectionData: Identifiable {
    let id: String
    let title: String
    let frames: [Frame]
    let completedFrames: Int?
    let totalFrames: Int?
    let showHeader: Bool
}

// MARK: - Creative Grid Section

struct CreativeGridSection: View {
    let section: GridSectionData
    let onFrameTap: (String) -> Void
    let columnCount: Int
    let forceThinCrosses: Bool
    let showDescriptions: Bool
    let showFullDescriptions: Bool
    let showTags: Bool
    let showFrameTimeOverlay: Bool
    let fontScale: CGFloat
    let coordinateSpaceName: String
    let viewportHeight: CGFloat
    let primaryAsset: (Frame) -> FrameAssetItem?
    let onStatusSelected: (Frame, FrameStatus) -> Void
    let showSkeleton: Bool
    let isPinching: Bool
    let updatingFrameIds: Set<String>

    init(
        section: GridSectionData,
        onFrameTap: @escaping (String) -> Void,
        columnCount: Int,
        forceThinCrosses: Bool,
        showDescriptions: Bool,
        showFullDescriptions: Bool,
        showTags: Bool,
        showFrameTimeOverlay: Bool,
        fontScale: CGFloat,
        coordinateSpaceName: String,
        viewportHeight: CGFloat,
        primaryAsset: @escaping (Frame) -> FrameAssetItem?,
        onStatusSelected: @escaping (Frame, FrameStatus) -> Void,
        showSkeleton: Bool,
        isPinching: Bool,
        updatingFrameIds: Set<String>
    ) {
        self.section = section
        self.onFrameTap = onFrameTap
        self.columnCount = columnCount
        self.forceThinCrosses = forceThinCrosses
        self.showDescriptions = showDescriptions
        self.showFullDescriptions = showFullDescriptions
        self.showTags = showTags
        self.showFrameTimeOverlay = showFrameTimeOverlay
        self.fontScale = fontScale
        self.coordinateSpaceName = coordinateSpaceName
        self.viewportHeight = viewportHeight
        self.primaryAsset = primaryAsset
        self.onStatusSelected = onStatusSelected
        self.showSkeleton = showSkeleton
        self.isPinching = isPinching
        self.updatingFrameIds = updatingFrameIds
    }

    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    private var columns: [GridItem] {
        let count = max(1, columnCount)
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if section.showHeader {
                VStack(){
                    TrackableHeader(id: section.id, title: section.title, coordSpace: coordinateSpaceName)

                    if let completed = section.completedFrames, let total = section.totalFrames {
                        VStack(alignment: .leading, spacing: 6) {
                            

                            HStack(spacing: 4) {
                                Text("\(completed) completed")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)

                                Text("•")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)

                                Text("\(total) total")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal)
                        
                        HStack {
                            ProgressView(value: Double(completed), total: Double(max(total, 1)))
                                .tint(.martiniDefaultColor)
                                .accessibilityLabel("\(completed) of \(total) frames complete")
                                .animation(.timingCurve(0.2, 0.0, 0.0, 1.0, duration: 0.35), value: Double(completed))
                        }
                        .padding(.horizontal, 14)
                    }
                }
            }

            // Grid of frames
            LazyVGrid(columns: columns, spacing: 8) {
                if showSkeleton {
                    ForEach(0..<max(columnCount * 2, columnCount * 3), id: \.self) { _ in
                        SkeletonGridCell()
                    }
                } else {
                    ForEach(section.frames) { frame in
                        Button {
                            onFrameTap(frame.id)
                        } label: {
                                GridFrameCell(
                                    frame: frame,
                                    primaryAsset: primaryAsset(frame),
                                    forceThinCrosses: forceThinCrosses,
                                    showDescription: showDescriptions,
                                    showFullDescription: showFullDescriptions,
                                    showTags: showTags,
                                    showFrameTimeOverlay: showFrameTimeOverlay,
                                    fontScale: fontScale,
                                    coordinateSpaceName: coordinateSpaceName,
                                    viewportHeight: viewportHeight,
                                    isUpdating: updatingFrameIds.contains(frame.id),
                                    onStatusSelected: { status in
                                        onStatusSelected(frame, status)
                                    }
                            )
                        }
                        .id(frame.id)
                        .allowsHitTesting(!isPinching && !updatingFrameIds.contains(frame.id))
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
    var primaryAsset: FrameAssetItem?
    var forceThinCrosses: Bool = false
    var showDescription: Bool = false
    var showFullDescription: Bool = false
    var showTags: Bool = false
    var showFrameTimeOverlay: Bool = true
    var fontScale: CGFloat
    let coordinateSpaceName: String
    let viewportHeight: CGFloat
    var isUpdating: Bool = false
    var onStatusSelected: (FrameStatus) -> Void
    @EnvironmentObject private var authService: AuthService

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FrameLayout(
                frame: frame,
                primaryAsset: primaryAsset,
                title: frame.caption,
                showFrameTimeOverlay: showFrameTimeOverlay,
                showTextBlock: false,
                cornerRadius: 6,
                enablesFullScreen: false,
                doneCrossLineWidthOverride: forceThinCrosses ? 1 : nil,
                usePinnedBoardMarkupFallback: true
            )
            .overlay {
                if isUpdating {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.6))
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(1.1)
                            .accessibilityLabel("Updating status")
                    }
                }
            }
            .contextMenu {
                statusMenu
            }
            if showDescription, let desc = frame.description, !desc.isEmpty {
                let baseFontSize = 12 * fontScale
                Text(plainTextFromHTML(desc))
                    .font(.system(size: baseFontSize))
                    .foregroundColor(.martiniDefaultDescriptionColor)
                    .lineLimit(showFullDescription ? nil : 3)
            }
            if showTags, !tagItems.isEmpty {
                let baseFontSize = 12 * fontScale
                let tagFontSize = max(8, baseFontSize - 1)
                GridTagFlowLayout(spacing: 4) {
                    ForEach(tagItems) { item in
                        Text(item.tag.name)
                            .font(.system(size: tagFontSize))
                            .foregroundColor(tagGroupColor(for: item.groupName))
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(tagGroupColor(for: item.groupName)).opacity(0.2)
                            )
                    }
                }
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
        ForEach(statusOptions, id: \.self) { status in
            Button {
                triggerStatusHaptic(for: status)
                onStatusSelected(status)
            } label: {
                Label(status.displayName, systemImage: status.systemImageName)
            }
        }
    }

    private var statusOptions: [FrameStatus] {
        var options: [FrameStatus] = [.done, .here, .next, .omit]
        if frame.statusEnum != .none {
            options.append(.none)
        }
        return options
    }

    private var tagItems: [GridTagItem] {
        guard let tags = frame.tags, !tags.isEmpty else { return [] }
        let grouped = Dictionary(grouping: tags) { tag -> String in
            let group = tag.groupName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (group?.isEmpty == false ? group : nil) ?? "Tags"
        }

        return grouped.flatMap { key, tags in
            let sortedTags = Array(Set(tags)).sorted { $0.name.lowercased() < $1.name.lowercased() }
            return sortedTags.map { tag in
                GridTagItem(id: tag.id ?? "\(key)-\(tag.name.lowercased())", tag: tag, groupName: key)
            }
        }
        .filter { !$0.tag.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .sorted { lhs, rhs in
            if lhs.groupName == rhs.groupName {
                return lhs.tag.name.lowercased() < rhs.tag.name.lowercased()
            }
            if lhs.groupName == "Tags" { return true }
            if rhs.groupName == "Tags" { return false }
            return lhs.groupName.lowercased() < rhs.groupName.lowercased()
        }
    }

    private func tagGroupColor(for groupName: String) -> Color {
        let normalized = groupName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let resolvedColorValue = tagGroupColorValue(for: normalized)

        if let resolved = colorFromTagGroupValue(resolvedColorValue) {
            return resolved
        }

        switch resolvedColorValue {
        case "blue":
            return .martiniBlueColor
        case "cyan":
            return .martiniCyanColor
        case "green":
            return .martiniGreenColor
        case "lime":
            return .martiniLimeColor
        case "orange":
            return .martiniOrangeColor
        case "pink":
            return .martiniPinkColor
        case "purple":
            return .martiniPurpleColor
        case "red":
            return .martiniRedColor
        case "yellow":
            return .martiniYellowColor
        default:
            return .martiniGrayColor
        }
    }

    private func tagGroupColorValue(for normalizedGroupName: String) -> String {
        let matchedGroup = authService.tagGroups.first {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedGroupName
        }

        let rawColor = matchedGroup?.color?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return rawColor?.isEmpty == false ? rawColor! : normalizedGroupName
    }

    private func colorFromTagGroupValue(_ value: String) -> Color? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else { return nil }

        let hexString = cleaned.hasPrefix("#") ? String(cleaned.dropFirst()) : cleaned
        guard hexString.count == 6 || hexString.count == 8 else { return nil }
        guard hexString.range(of: "^[0-9a-f]+$", options: .regularExpression) != nil else { return nil }

        var hexNumber: UInt64 = 0
        guard Scanner(string: hexString).scanHexInt64(&hexNumber) else { return nil }

        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        if hexString.count == 8 {
            red = Double((hexNumber & 0xFF000000) >> 24) / 255
            green = Double((hexNumber & 0x00FF0000) >> 16) / 255
            blue = Double((hexNumber & 0x0000FF00) >> 8) / 255
            alpha = Double(hexNumber & 0x000000FF) / 255
        } else {
            red = Double((hexNumber & 0xFF0000) >> 16) / 255
            green = Double((hexNumber & 0x00FF00) >> 8) / 255
            blue = Double(hexNumber & 0x0000FF) / 255
            alpha = 1.0
        }

        return Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}

private struct GridTagItem: Identifiable {
    let id: String
    let tag: FrameTag
    let groupName: String
}

private struct GridTagFlowLayout: Layout {
    let spacing: CGFloat

    init(spacing: CGFloat) {
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        let layout = layoutRows(maxWidth: maxWidth, subviews: subviews)
        let totalHeight = layout.rows.reduce(0) { $0 + $1.height } + spacing * max(0, CGFloat(layout.rows.count - 1))
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = layoutRows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY

        for row in layout.rows {
            var x = bounds.minX
            for index in row.indices {
                let subview = subviews[index]
                let size = layout.sizes[index]
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func layoutRows(maxWidth: CGFloat, subviews: Subviews) -> (rows: [Row], sizes: [CGSize]) {
        var rows: [Row] = []
        var currentRow = Row()
        var sizes: [CGSize] = Array(repeating: .zero, count: subviews.count)

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            sizes[index] = size

            if currentRow.indices.isEmpty {
                currentRow.indices.append(index)
                currentRow.width = size.width
                currentRow.height = max(currentRow.height, size.height)
                continue
            }

            let candidateWidth = currentRow.width + spacing + size.width
            if candidateWidth <= maxWidth {
                currentRow.indices.append(index)
                currentRow.width = candidateWidth
                currentRow.height = max(currentRow.height, size.height)
            } else {
                rows.append(currentRow)
                currentRow = Row(indices: [index], width: size.width, height: size.height)
            }
        }

        if !currentRow.indices.isEmpty {
            rows.append(currentRow)
        }

        return (rows, sizes)
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }
}

// MARK: - Skeleton Grid Loader

struct SkeletonGridPlaceholder: View {
    let columnCount: Int

    private var columns: [GridItem] {
        let count = max(1, columnCount)
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    private var placeholderItems: Int {
        max(columnCount * 3, columnCount * 2)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(0..<placeholderItems, id: \.self) { _ in
                    SkeletonGridCell()
                }
            }
            .padding(.horizontal)
            .padding(.vertical)
        }
    }
}

struct SkeletonGridCell: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FrameLayout.ShimmerView(cornerRadius: 6)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)

            FrameLayout.ShimmerView(cornerRadius: 4)
                .frame(width: 120, height: 10, alignment: .leading)
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
    let showHeader: Bool
    let progress: ProgressCounts

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Creative header
            if showHeader {
                VStack(alignment: .leading, spacing: 4) {
                    Text(creative.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.horizontal)

                    HStack {
                        Text("\(progress.completed)/\(progress.total) frames")
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
        case "here":
            return .martiniDefaultColor
        case "next":
            return .orange
        case "done":
            return .green
        case "omit":
            return .gray
        default:
            return .secondary
        }
    }
}

enum FrameStatus: String {
    case done = "done"
    case here = "here"
    case next = "next"
    case omit = "omit"
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
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @AppStorage("themePreference") private var themePreferenceRawValue = ThemePreference.system.rawValue
    @Binding var showDescriptions: Bool
    @Binding var showFullDescriptions: Bool
    @Binding var showGridTags: Bool
    @Binding var gridSizeStep: Int // 1..4 (portrait: 4->1, landscape: 5->2)
    @Binding var gridFontStep: Int // 1..5
    @Binding var gridPriority: FrameAssetKind
    @Binding var doneCrossLineWidth: Double
    @Binding var showDoneCrosses: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Grid") {
                    Toggle("Show Descriptions", isOn: $showDescriptions)

                    Toggle("Show Full Descriptions", isOn: $showFullDescriptions)
                        .disabled(!showDescriptions)

                    Toggle("Show Tags", isOn: $showGridTags)

                    // Grid size slider: portrait 4/3/2/1, landscape 5/4/3/2 (handled by gridColumnCount)
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

                Section("Markers") {
                    VStack(alignment: .leading) {
                        Text("Crosses Thickness")
                        HStack {
                            //Image(systemName: "line.diagonal")
                            //Spacer()
                            Slider(value: $doneCrossLineWidth, in: 1...12, step: 0.5)
                            //Spacer()
                            //Image(systemName: "line.diagonal.arrow")
                        }
                    }
                    VStack(alignment: .leading) {
                        Toggle("Show Crosses", isOn: $showDoneCrosses)
                    }
                }

                Section("Theme") {
                    HStack(spacing: 6) {
                        ForEach(ThemePreference.allCases) { preference in
                            let isSelected = themePreferenceBinding.wrappedValue == preference
                            Button {
                                themePreferenceBinding.wrappedValue = preference
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: preference.systemImageName)
                                        .font(.system(size: 16, weight: .semibold))
                                    Text(preference.label)
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundStyle(isSelected ? Color.white : Color.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(isSelected
                                              ? Color.accentColor
                                              : Color.secondary.opacity(0.15))
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(preference.label)
                            .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
                        }
                    }
                }

                Section {
                    NavigationLink {
                        ScoutCameraSettingsView()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Scout Camera")
                            Text("Manage cameras and lenses")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Account") {
                    Button(role: .destructive) {
                        authService.logout()
                        dismiss()
                    } label: {
                        Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
//            .toolbar {
//                ToolbarItem(placement: .topBarLeading) {
//                    Button {
//                        dismiss()
//                    } label: {
//                        Image(systemName: "xmark")
//                    }
//                    .accessibilityLabel("Close settings")
//                }
//            }
        }
        .tint(.martiniDefaultColor)
    }

    private var gridSizeLabel: String {
        switch gridSizeStep {
        case 1: return "Small"
        case 2: return "Small+"
        case 3: return "Medium"
        case 4: return "Large"
        default: return "Adaptive"
        }
    }

    private var themePreferenceBinding: Binding<ThemePreference> {
        Binding(
            get: { ThemePreference(rawValue: themePreferenceRawValue) ?? .system },
            set: { themePreferenceRawValue = $0.rawValue }
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthService())
}
