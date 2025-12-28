import SwiftUI

struct SchedulesView: View {
    let schedule: ProjectSchedule
    let onSelect: (ProjectScheduleItem) -> Void

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
                                    .foregroundStyle(.white)
                                
                                if let startTime = entry.startTime {
                                    Label(startTime, systemImage: "clock")
                                        .foregroundStyle(.gray)
                                        .font(.footnote)
                                }
                                
                                //if let duration = scheduleDuration {
                                    Label("Duration: 12h", systemImage: "timer")
                                        .foregroundStyle(.gray)
                                        .font(.footnote)
                                //}
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(10)
                    .background(.markerPopup)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            Spacer()
        }
        .padding(10)
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
