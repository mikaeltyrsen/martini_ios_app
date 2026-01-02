import SwiftUI

struct ScheduleView: View {
    let schedule: ProjectSchedule
    let item: ProjectScheduleItem

    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var frameAssetOrders: [String: [FrameAssetKind]] = [:]
    @State private var showsTimelineProgress = true
    private var scheduleGroups: [ScheduleGroup] { item.groups ?? schedule.groups ?? [] }

    private var scheduleTitle: String { item.title.isEmpty ? (schedule.title ?? schedule.name) : item.title }
    private var scheduleDate: String? { schedule.date ?? item.date }
    private var scheduleStartTime: String? { schedule.startTime ?? item.startTime }
    private var scheduleDuration: Int? { schedule.durationMinutes ?? item.durationMinutes ?? item.duration }
    private var flattenedBlocks: [ScheduleBlock] { scheduleGroups.flatMap(\.blocks) }

    private static let scheduleDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private var formattedDate: String? {
        scheduleDate.map { formattedScheduleDate(from: $0, includeYear: true) }
    }

    private var formattedStartTime: String? {
        scheduleStartTime.map { formattedTimeFrom24Hour($0) }
    }

    private var isLandscape: Bool {
        verticalSizeClass == .compact
    }

    private var showsWideLayout: Bool {
        horizontalSizeClass == .regular || isLandscape
    }

    private var isPortraitPhone: Bool {
        horizontalSizeClass == .compact && !isLandscape
    }

    private func timeAndDurationText(startTime: String?, duration: Int?) -> String? {
        let timeText = startTime.map { formattedTimeFrom24Hour($0) }
        let durationText = duration.map { formattedDuration(fromMinutes: $0) }

        switch (timeText, durationText) {
        case let (time?, duration?):
            return "\(time) • \(duration)"
        case let (time?, nil):
            return time
        case let (nil, duration?):
            return duration
        default:
            return nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                
                if scheduleGroups.isEmpty {
                    Text("No schedule blocks available.")
                        .foregroundStyle(.secondary)
                } else {
                    scheduleContent
                }
            }
            .padding()
        }
        .navigationTitle(scheduleTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button {
                    showsTimelineProgress.toggle()
                } label: {
                    Image(systemName: showsTimelineProgress ? "clock.fill" : "clock")
                }
                .accessibilityLabel(showsTimelineProgress ? "Hide schedule progress" : "Show schedule progress")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(scheduleTitle)
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            if let date = formattedDate {
                Text(date)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let startTime = formattedStartTime {
                Label(startTime, systemImage: "clock")
                    .foregroundStyle(.secondary)
            }

            if let lastUpdated = item.lastUpdated {
                Label("Updated: \(lastUpdated)", systemImage: "arrow.clockwise")
                    .foregroundStyle(.secondary)
            }

            if let duration = scheduleDuration {
                Label("Duration: \(formattedDuration(fromMinutes: duration))", systemImage: "timer")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var scheduleContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(scheduleGroups) { group in
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(group.blocks) { block in
                            blockRow(for: block)
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        }
        .coordinateSpace(name: "timeline")
        .backgroundPreferenceValue(TimelineRowAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if showsTimelineProgress {
                    timelineProgressLine(with: anchors, proxy: proxy)
                }
            }
        }
    }

    @ViewBuilder
    private func blockRow(for block: ScheduleBlock) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if showsTimelineProgress {
                timelineIndicator(for: block)
                    .anchorPreference(key: TimelineRowAnchorKey.self, value: .bounds) { anchor in
                        [block.id: anchor]
                    }
            }
            blockView(for: block)
        }
    }

    @ViewBuilder
    private func blockView(for block: ScheduleBlock) -> some View {
        switch block.type {
        case .title:
            HStack(alignment: .center, spacing: 12) {
                if isPortraitPhone {
                    VStack(alignment: .center, spacing: 4) {
                        titleRowTimeAndDuration(for: block)
                        Text(block.title ?? "")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        titleRowTimeAndDuration(for: block)
                        Text(block.title ?? "")
                            .font(.headline)
                    }
                    if showsWideLayout, let description = block.description, !description.isEmpty {
                        Spacer(minLength: 0)
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(Color.martiniDefaultDescriptionColor)
                    }
                }
            }
            .padding(12)
            .background(blockColor(block.color))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .shot, .unknown:
            Group {
                if showsWideLayout {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            storyboardTimeAndDuration(for: block)
                        }

                        storyboardGrid(for: block)
                        
                        if let description = block.description, !description.isEmpty {
                            Text(description)
                                .font(.subheadline)
                                .foregroundStyle(Color.martiniDefaultDescriptionColor)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 8) {
                            storyboardTimeAndDuration(for: block)
                        }

                        storyboardGrid(for: block)
                    }
                }
            }
            .padding(12)
            .background(blockColor(block.color))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(isStoryboardRowComplete(for: block) ? 0.5 : 1)
        }
    }

    @ViewBuilder
    private func storyboardGrid(for block: ScheduleBlock) -> some View {
        let frames = frames(for: block)

        if frames.isEmpty {
            Text("No matching storyboards found.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                ForEach(frames) { frame in
                    NavigationLink {
                        FrameView(
                            frame: frame,
                            assetOrder: assetOrderBinding(for: frame),
                            onClose: { dismiss() }
                        )
                    } label: {
                        FrameLayout(
                            frame: frame,
                            showStatusBadge: false,
                            showFrameTimeOverlay: false,
                            showTextBlock: false,
                            enablesFullScreen: false
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func frames(for block: ScheduleBlock) -> [Frame] {
        guard let storyboardIds = block.storyboards else { return [] }

        return storyboardIds.compactMap { id in
            authService.frames.first { $0.id == id }
        }
    }

    private func isStoryboardRowComplete(for block: ScheduleBlock) -> Bool {
        let rowFrames = frames(for: block)
        guard !rowFrames.isEmpty else { return false }
        return rowFrames.allSatisfy(isFrameComplete)
    }

    private func blockColor(_ name: String?) -> Color {
        switch name?.lowercased() {
        case "blue": return .martiniBlueColor
        case "yellow": return .martiniYellowColor
        case "green": return .martiniGreenColor
        case "red": return .martiniRedColor
        case "orange": return .martiniOrangeColor
        case "cyan": return .martiniCyanColor
        case "pink": return .martiniPinkColor
        case "purple": return .martiniPurpleColor
        case "lime": return .martiniLimeColor
        case "gray": return .martiniGrayColor
        default: return .scheduleBackground
        }
    }

    private func assetOrder(for frame: Frame) -> [FrameAssetKind] {
        frameAssetOrders[frame.id] ?? frame.availableAssets.map(\.kind)
    }

    private func assetOrderBinding(for frame: Frame) -> Binding<[FrameAssetKind]> {
        Binding(
            get: { assetOrder(for: frame) },
            set: { frameAssetOrders[frame.id] = $0 }
        )
    }

    @ViewBuilder
    private func titleRowTimeAndDuration(for block: ScheduleBlock) -> some View {
        if let text = timeAndDurationText(startTime: block.calculatedStart, duration: block.duration) {
            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func storyboardTimeAndDuration(for block: ScheduleBlock) -> some View {
        if let timeText = timeAndDurationText(startTime: block.calculatedStart, duration: block.duration) {
//            let icon = block.calculatedStart != nil ? "clock" : "timer"
//            Label(timeText, systemImage: icon)
//                .font(.footnote.weight(.semibold))
//                .foregroundStyle(.secondary)
            Text(timeText)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private enum TimelineMarker {
        case warning
        case currentTime
        case here

        var icon: String {
            switch self {
            case .warning:
                return "exclamationmark.triangle.fill"
            case .currentTime:
                return "clock"
            case .here:
                return "camera.fill"
            }
        }
    }

    private enum TimelineProgressState {
        case ahead
        case behind
        case onTime
    }

    private struct TimelineRowAnchorKey: PreferenceKey {
        static var defaultValue: [String: Anchor<CGRect>] = [:]

        static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
            value.merge(nextValue(), uniquingKeysWith: { $1 })
        }
    }

    private let timelineIndicatorWidth: CGFloat = 28
    private let timelineLineWidth: CGFloat = 3
    private let timelineMarkerSize: CGFloat = 24

    private var scheduleBaseDate: Date {
        if let scheduleDate,
           let date = ScheduleView.scheduleDateFormatter.date(from: scheduleDate) {
            return date
        }
        return Calendar.current.startOfDay(for: Date())
    }

    private var currentScheduleTime: Date {
        let nowComponents = Calendar.current.dateComponents([.hour, .minute, .second], from: Date())
        return Calendar.current.date(
            bySettingHour: nowComponents.hour ?? 0,
            minute: nowComponents.minute ?? 0,
            second: nowComponents.second ?? 0,
            of: scheduleBaseDate
        ) ?? Date()
    }

    private func dateForScheduleTime(_ timeString: String?) -> Date? {
        guard let timeString, !timeString.isEmpty else { return nil }
        let components = timeString.split(separator: ":")
        guard components.count >= 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]) else {
            return nil
        }
        let second = components.count > 2 ? Int(components[2]) ?? 0 : 0
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: second, of: scheduleBaseDate)
    }

    private func startDate(for block: ScheduleBlock) -> Date? {
        guard block.ignoreTime != true else { return nil }
        return dateForScheduleTime(block.calculatedStart)
    }

    private var blocksWithStartTimes: [(block: ScheduleBlock, date: Date)] {
        flattenedBlocks.compactMap { block in
            guard let date = startDate(for: block) else { return nil }
            return (block, date)
        }
    }

    private var hereBlock: ScheduleBlock? {
        flattenedBlocks.first { block in
            frames(for: block).contains { $0.statusEnum == .here }
        }
    }

    private var hereTime: Date? {
        guard let block = hereBlock else { return nil }
        return startDate(for: block)
    }

    private var progressState: TimelineProgressState? {
        guard let hereTime else { return nil }
        if hereTime > currentScheduleTime {
            return .ahead
        }
        if hereTime < currentScheduleTime {
            return .behind
        }
        return .onTime
    }

    private var progressColor: Color? {
        switch progressState {
        case .ahead, .onTime:
            return .green
        case .behind:
            return .red
        case .none:
            return nil
        }
    }

    private var progressRange: ClosedRange<Date>? {
        guard let hereTime else { return nil }
        let now = currentScheduleTime
        if hereTime <= now {
            return hereTime...now
        }
        return now...hereTime
    }

    private var currentTimeBlockId: String? {
        guard let closest = blocksWithStartTimes.min(by: { lhs, rhs in
            abs(lhs.date.timeIntervalSince(currentScheduleTime)) < abs(rhs.date.timeIntervalSince(currentScheduleTime))
        }) else {
            return nil
        }
        return closest.block.id
    }

    private func isBlockOverdue(_ block: ScheduleBlock) -> Bool {
        guard let blockDate = startDate(for: block),
              blockDate < currentScheduleTime else {
            return false
        }
        let blockFrames = frames(for: block)
        guard !blockFrames.isEmpty else { return false }
        return !blockFrames.allSatisfy(isFrameComplete)
    }

    private func isFrameComplete(_ frame: Frame) -> Bool {
        frame.statusEnum == .done || frame.statusEnum == .omit
    }

    private func isInProgressRange(_ block: ScheduleBlock) -> Bool {
        guard let range = progressRange,
              let blockDate = startDate(for: block) else {
            return false
        }
        return range.contains(blockDate)
    }

    private func marker(for block: ScheduleBlock) -> TimelineMarker? {
        if let hereBlock, block.id == hereBlock.id {
            return .here
        }
        if let currentTimeBlockId, block.id == currentTimeBlockId {
            return .currentTime
        }
        if isBlockOverdue(block) {
            return .warning
        }
        return nil
    }

    private func markerColor(for marker: TimelineMarker) -> Color {
        switch marker {
        case .warning:
            return .orange
        case .currentTime, .here:
            return progressColor ?? .martiniDefaultColor
        }
    }

    private func timelineIndicator(for block: ScheduleBlock) -> some View {
        let marker = marker(for: block)
        return ZStack {
            if let marker {
                Circle()
                    .fill(markerColor(for: marker))
                    .frame(width: timelineMarkerSize, height: timelineMarkerSize)
                    .overlay {
                        Image(systemName: marker.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            }
        }
        .frame(width: timelineIndicatorWidth)
    }

    @ViewBuilder
    private func timelineProgressLine(
        with anchors: [String: Anchor<CGRect>],
        proxy: GeometryProxy
    ) -> some View {
        let timelineBlocks = scheduleGroups.flatMap(\.blocks)
        let positions = timelineBlocks.compactMap { block -> (block: ScheduleBlock, midY: CGFloat)? in
            guard let anchor = anchors[block.id] else { return nil }
            let rect = proxy[anchor]
            return (block, rect.midY)
        }
        guard let first = positions.first, let last = positions.last else {
            EmptyView()
            return
        }

        let x = timelineIndicatorWidth / 2
        let basePath = Path { path in
            path.move(to: CGPoint(x: x, y: first.midY))
            path.addLine(to: CGPoint(x: x, y: last.midY))
        }
        basePath
            .stroke(Color.gray.opacity(0.35), style: StrokeStyle(lineWidth: timelineLineWidth, lineCap: .round))

        if let progressColor {
            let positionsById = Dictionary(uniqueKeysWithValues: positions.map { ($0.block.id, $0.midY) })
            let markerRadius = timelineMarkerSize / 2
            var fillStart = hereBlock.flatMap { positionsById[$0.id] }
            var fillEnd = currentTimeBlockId.flatMap { positionsById[$0] }

            if fillStart == nil || fillEnd == nil {
                let inRange = positions.filter { isInProgressRange($0.block) }.map(\.midY)
                fillStart = inRange.min()
                fillEnd = inRange.max()
            }

            if var fillStart, var fillEnd {
                if fillStart < fillEnd {
                    fillStart += markerRadius
                    fillEnd -= markerRadius
                } else if fillStart > fillEnd {
                    fillStart -= markerRadius
                    fillEnd += markerRadius
                }

                if fillStart != fillEnd {
                    let fillPath = Path { path in
                        path.move(to: CGPoint(x: x, y: fillStart))
                        path.addLine(to: CGPoint(x: x, y: fillEnd))
                    }
                    fillPath
                        .stroke(progressColor, style: StrokeStyle(lineWidth: timelineLineWidth, lineCap: .round))
                }
            }
        }
    }
}
