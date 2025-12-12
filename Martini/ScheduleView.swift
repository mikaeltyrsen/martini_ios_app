import SwiftUI

struct ScheduleView: View {
    let schedule: ProjectSchedule
    let item: ProjectScheduleItem

    @EnvironmentObject private var authService: AuthService
    @State private var fetchedSchedule: ProjectSchedule?
    @State private var isLoading = true
    @State private var dataError: String?

    private var resolvedSchedule: ProjectSchedule { fetchedSchedule ?? schedule }
    private var scheduleGroups: [ScheduleGroup] { resolvedSchedule.groups ?? [] }

    private var scheduleTitle: String { resolvedSchedule.title ?? item.title }
    private var scheduleDate: String? { resolvedSchedule.date ?? item.date }
    private var scheduleStartTime: String? { resolvedSchedule.startTime ?? item.startTime }
    private var scheduleDuration: Int? { resolvedSchedule.durationMinutes ?? item.durationMinutes ?? item.duration }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let error = dataError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }

                if isLoading {
                    HStack {
                        ProgressView()
                        Text("Loading schedule…")
                            .foregroundStyle(.secondary)
                    }
                } else if scheduleGroups.isEmpty {
                    Text("No schedule blocks available.")
                        .foregroundStyle(.secondary)
                } else {
                    scheduleContent
                }
            }
            .padding()
        }
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadSchedule()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(schedule.name)
                .font(.headline)
            Text(scheduleTitle)
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            if let date = scheduleDate {
                Label(date, systemImage: "calendar")
                    .foregroundStyle(.secondary)
            }

            if let startTime = scheduleStartTime {
                Label(startTime, systemImage: "clock")
                    .foregroundStyle(.secondary)
            }

            if let lastUpdated = item.lastUpdated {
                Label("Updated: \(lastUpdated)", systemImage: "arrow.clockwise")
                    .foregroundStyle(.secondary)
            }

            if let duration = scheduleDuration {
                Label("Duration: \(duration) min", systemImage: "timer")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var scheduleContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(scheduleGroups) { group in
                VStack(alignment: .leading, spacing: 10) {
                    if !group.title.isEmpty {
                        Text(group.title)
                            .font(.headline)
                    }

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
                    Text(time)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(block.title ?? "")
                    .font(.headline)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(blockColor(block.color))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .shot, .unknown:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if let time = block.calculatedStart {
                        Label(time, systemImage: "clock")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    if let duration = block.duration {
                        Label("\(duration) min", systemImage: "timer")
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                ForEach(frames) { frame in
                    FrameLayout(frame: frame, showStatusBadge: false)
                        .frame(maxWidth: .infinity)
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

    @MainActor
    private func loadSchedule() async {
        isLoading = true
        dataError = nil

        do {
            let latest = try await authService.fetchSchedule(for: item.id ?? schedule.id)
            fetchedSchedule = latest
        } catch {
            dataError = error.localizedDescription
        }

        isLoading = false
    }
}
