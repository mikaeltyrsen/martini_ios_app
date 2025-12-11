import SwiftUI

struct SchedulesView: View {
    let schedule: ProjectSchedule
    let onSelect: (ProjectScheduleItem) -> Void

    var body: some View {
        List {
            Section(schedule.name) {
                ForEach(schedule.schedules ?? [], id: \.listIdentifier) { entry in
                    Button {
                        onSelect(entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title)
                                .font(.headline)

                            if let date = entry.date {
                                Text(date)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            if let startTime = entry.startTime {
                                Text(startTime)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .navigationTitle("Schedules")
        .navigationBarTitleDisplayMode(.inline)
    }
}
