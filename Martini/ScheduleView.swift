import SwiftUI

struct ScheduleView: View {
    let schedule: ProjectSchedule
    let item: ProjectScheduleItem

    private var jsonString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let data = try? encoder.encode(item),
           let string = String(data: data, encoding: .utf8) {
            return string
        }

        return "Unable to load schedule JSON."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(schedule.name)
                        .font(.headline)
                    Text(item.title)
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let date = item.date {
                    Label(date, systemImage: "calendar")
                        .foregroundStyle(.secondary)
                }

                if let startTime = item.startTime {
                    Label(startTime, systemImage: "clock")
                        .foregroundStyle(.secondary)
                }

                if let lastUpdated = item.lastUpdated {
                    Label("Updated: \(lastUpdated)", systemImage: "arrow.clockwise")
                        .foregroundStyle(.secondary)
                }

                if let duration = item.duration {
                    Label("Duration: \(duration) min", systemImage: "timer")
                        .foregroundStyle(.secondary)
                }

                Divider()

                Text("Schedule JSON")
                    .font(.headline)

                ScrollView(.horizontal) {
                    Text(jsonString)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
    }
}
