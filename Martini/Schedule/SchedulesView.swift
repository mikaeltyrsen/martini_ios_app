import SwiftUI

struct SchedulesView: View {
    let schedule: ProjectSchedule
    let onSelect: (ProjectScheduleItem) -> Void

    @EnvironmentObject private var authService: AuthService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private func entryDuration(for entry: ProjectScheduleItem) -> Int? {
        entry.durationMinutes ?? entry.duration
    }

    private func timeAndDurationText(for entry: ProjectScheduleItem) -> String? {
        let timeText = entry.startTime.map { formattedTimeFrom24Hour($0) }
        let durationText = entryDuration(for: entry).map { formattedDuration(fromMinutes: $0) }

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

    private func isEntryComplete(_ entry: ProjectScheduleItem) -> Bool {
        let groups = entry.groups ?? schedule.groups ?? []
        let storyboardIds = Set(groups.flatMap { group in
            group.blocks.flatMap { $0.storyboards ?? [] }
        })

        guard !storyboardIds.isEmpty else { return false }

        let frames = storyboardIds.compactMap { id in
            authService.frames.first { $0.id == id }
        }

        guard frames.count == storyboardIds.count else { return false }

        return frames.allSatisfy(isFrameComplete)
    }

    private func isFrameComplete(_ frame: Frame) -> Bool {
        frame.statusEnum == .done || frame.statusEnum == .omit
    }

    var body: some View {
        Section(){
            VStack(alignment: .leading, spacing: 10){
                ForEach(schedule.schedules ?? [], id: \.listIdentifier) { entry in
                    Button {
                        onSelect(entry)
                    } label: {
                        HStack(spacing: 14){
                            if let dateString = entry.date,
                               let parsedDate = try? Date(dateString, strategy: .iso8601.year().month().day()) {

                                VStack(spacing: 0) {
                                    Text(parsedDate.formatted(.dateTime.day()))
                                        .font(.system(size: 30, weight: .semibold))
                                        .foregroundStyle(.white)

                                    Text(parsedDate.formatted(.dateTime.month(.abbreviated)).uppercased())
                                        .font(.system(size: 8, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                                .frame(width: 40)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.martiniDefault)))
                            }

                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.title)
                                    .font(.system(size: 24, weight: .semibold))

                                if let timeAndDuration = timeAndDurationText(for: entry) {
                                    Text(timeAndDuration)
                                        .foregroundStyle(.gray)
                                        .font(.footnote)
                                        .frame(
                                            maxWidth: .infinity,
                                            alignment: horizontalSizeClass == .compact ? .center : .leading
                                        )
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(10)
                    .background(.markerPopup)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .opacity(isEntryComplete(entry) ? 0.5 : 1)
                }
            }
            Spacer()
        }
        .padding(10)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("Schedule")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(schedule.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }
        }
//        List {
//            Section(schedule.name) {
//                ForEach(schedule.schedules ?? [], id: \.listIdentifier) { entry in
//                    Button {
//                        onSelect(entry)
//                    } label: {
//                        VStack(alignment: .leading, spacing: 4) {
//                            Text(entry.title)
//                                .font(.headline)
//
//                            if let date = entry.date {
//                                Text(formattedScheduleDate(from: date, includeYear: true))
//                                    .font(.subheadline)
//                                    .foregroundStyle(.secondary)
//                            }
//
//                            if let startTime = entry.startTime {
//                                Text(formattedTimeFrom24Hour(startTime))
//                                    .font(.footnote)
//                                    .foregroundStyle(.secondary)
//                            }
//                        }
//                        .frame(maxWidth: .infinity, alignment: .leading)
//                    }
//                }
//            }
//        }
//        .navigationTitle("Schedules")
//        .navigationBarTitleDisplayMode(.inline)
    }
}
