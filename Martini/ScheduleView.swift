import SwiftUI

struct ScheduleView: View {
    let schedule: ProjectSchedule
    let item: ProjectScheduleItem

    @EnvironmentObject private var authService: AuthService
    private var scheduleGroups: [ScheduleGroup] { item.groups ?? schedule.groups ?? [] }

    private var scheduleTitle: String { item.title.isEmpty ? (schedule.title ?? schedule.name) : item.title }
    private var scheduleDate: String? { schedule.date ?? item.date }
    private var scheduleStartTime: String? { schedule.startTime ?? item.startTime }
    private var scheduleDuration: Int? { schedule.durationMinutes ?? item.durationMinutes ?? item.duration }

    private var formattedDate: String? {
        scheduleDate.map { formattedScheduleDate(from: $0, includeYear: true) }
    }

    private var formattedStartTime: String? {
        scheduleStartTime.map { formattedTimeFrom24Hour($0) }
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(schedule.name)
                .font(.headline)
            Text(scheduleTitle)
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            if let date = formattedDate {
                Label(date, systemImage: "calendar")
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
                            blockView(for: block)
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func blockView(for block: ScheduleBlock) -> some View {
        switch block.type {
        case .title:
            HStack(alignment: .center, spacing: 8) {
                if let time = block.calculatedStart {
                    Text(formattedTimeFrom24Hour(time))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(block.title ?? "")
                    .font(.headline)
                Spacer(minLength: 0)
                
                if let description = block.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(blockColor(block.color))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .shot, .unknown:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if let time = block.calculatedStart {
                        Label(formattedTimeFrom24Hour(time), systemImage: "clock")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    if let duration = block.duration {
                        Label(formattedDuration(fromMinutes: duration), systemImage: "timer")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                if let description = block.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                storyboardGrid(for: block)
            }
            .padding(.vertical, 8)
            .background(blockColor(block.color))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                    FrameLayout(frame: frame, showStatusBadge: false, showFrameTimeOverlay: false, enablesFullScreen: false)
                        .frame(maxWidth: 100)
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

    private func blockColor(_ name: String?) -> Color {
        switch name?.lowercased() {
        case "blue": return .blue.opacity(0.12)
        case "yellow": return .yellow.opacity(0.24)
        case "green": return .green.opacity(0.18)
        case "red": return .red.opacity(0.18)
        case "orange": return .orange.opacity(0.2)
        default: return Color.gray.opacity(0.12)
        }
    }
}
