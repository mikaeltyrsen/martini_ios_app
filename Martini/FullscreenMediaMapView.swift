import Foundation
import MapKit
import SwiftUI

struct ScoutMapSheetView: View {
    let title: String
    let coordinate: CLLocationCoordinate2D
    let headingDegrees: Double?
    let focalLengthMm: Double?
    let sensorWidthMm: Double?

    @State private var selectedDate = Date()
    @State private var cameraPosition: MapCameraPosition

    private let sunCalculator = SunPathCalculator()

    init(
        title: String,
        coordinate: CLLocationCoordinate2D,
        headingDegrees: Double?,
        focalLengthMm: Double?,
        sensorWidthMm: Double?
    ) {
        self.title = title
        self.coordinate = coordinate
        self.headingDegrees = headingDegrees
        self.focalLengthMm = focalLengthMm
        self.sensorWidthMm = sensorWidthMm
        let camera = MapCamera(
            centerCoordinate: coordinate,
            distance: 180,
            heading: 0,
            pitch: 0
        )
        _cameraPosition = State(initialValue: .camera(camera))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                datePicker
                mapView
                sunSummary
            }
            .padding()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var datePicker: some View {
        DatePicker("Date", selection: $selectedDate, displayedComponents: [.date])
            .datePickerStyle(.compact)
    }

    private var mapView: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
            }
            .mapStyle(.imagery(elevation: .realistic))
            .overlay {
                if let point = proxy.convert(coordinate, from: .local) {
                    ScoutMapOverlayView(
                        headingDegrees: headingDegrees ?? 0,
                        fovDegrees: fovDegrees,
                        sunPath: sunData?.path ?? [],
                        capsuleEntries: capsuleEntries
                    )
                    .position(point)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var sunSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let sunData {
                summaryRow(title: "Sunrise", value: timeFormatter.string(from: sunData.sunrise))
                summaryRow(title: "Sunset", value: timeFormatter.string(from: sunData.sunset))
            } else {
                Text("Sunrise/Sunset unavailable for selected date.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.system(size: 14, weight: .semibold))
    }

    private var sunData: SunData? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return sunCalculator.sunData(for: location, date: selectedDate, timeZone: .current)
    }

    private var capsuleEntries: [SunPathEntry] {
        guard let sunData else { return [] }
        var entries: [SunPathEntry] = []
        entries.append(sunCalculator.sunPosition(for: coordinate, date: sunData.sunrise))

        let calendar = Calendar.current
        let startHour = calendar.nextDate(
            after: sunData.sunrise,
            matching: DateComponents(minute: 0, second: 0),
            matchingPolicy: .nextTime
        )
        if var current = startHour {
            while current < sunData.sunset {
                entries.append(sunCalculator.sunPosition(for: coordinate, date: current))
                current = calendar.date(byAdding: .hour, value: 1, to: current) ?? sunData.sunset
            }
        }

        entries.append(sunCalculator.sunPosition(for: coordinate, date: sunData.sunset))
        return entries
    }

    private var fovDegrees: Double {
        guard let focalLengthMm, let sensorWidthMm, focalLengthMm > 0, sensorWidthMm > 0 else {
            return 50
        }
        let radians = 2 * atan(sensorWidthMm / (2 * focalLengthMm))
        return radians * 180 / .pi
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }
}

private struct ScoutMapOverlayView: View {
    let headingDegrees: Double
    let fovDegrees: Double
    let sunPath: [SunPathEntry]
    let capsuleEntries: [SunPathEntry]

    private let overlaySize: CGFloat = 260
    private let capsuleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    var body: some View {
        ZStack {
            sunPathOverlay
            cameraFOVOverlay
        }
        .frame(width: overlaySize, height: overlaySize)
    }

    private var cameraFOVOverlay: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = min(proxy.size.width, proxy.size.height) * 0.42
            let leftAngle = angleRadians(degrees: headingDegrees - fovDegrees / 2)
            let rightAngle = angleRadians(degrees: headingDegrees + fovDegrees / 2)

            Path { path in
                path.move(to: center)
                path.addLine(to: point(from: center, radius: radius, angle: leftAngle))
                path.move(to: center)
                path.addLine(to: point(from: center, radius: radius, angle: rightAngle))
            }
            .stroke(.cyan.opacity(0.9), lineWidth: 2)

            Path { path in
                path.move(to: point(from: center, radius: radius * 0.2, angle: leftAngle))
                path.addArc(
                    center: center,
                    radius: radius * 0.2,
                    startAngle: Angle(radians: leftAngle),
                    endAngle: Angle(radians: rightAngle),
                    clockwise: false
                )
            }
            .stroke(.cyan.opacity(0.6), lineWidth: 2)
        }
    }

    private var sunPathOverlay: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let maxRadius = min(proxy.size.width, proxy.size.height) * 0.48
            let minRadius = min(proxy.size.width, proxy.size.height) * 0.18
            Path { path in
                for (index, entry) in sunPath.enumerated() {
                    let radius = radiusForAltitude(entry.altitudeDegrees, min: minRadius, max: maxRadius)
                    let angle = angleRadians(degrees: entry.azimuthDegrees)
                    let point = point(from: center, radius: radius, angle: angle)
                    if index == 0 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }
            }
            .stroke(.yellow.opacity(0.85), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            ForEach(Array(capsuleEntries.enumerated()), id: \.offset) { _, entry in
                let radius = radiusForAltitude(entry.altitudeDegrees, min: minRadius, max: maxRadius)
                let angle = angleRadians(degrees: entry.azimuthDegrees)
                let point = point(from: center, radius: radius, angle: angle)
                let arrowAngle = arrowAngleRadians(from: point, to: center)
                SunTimeCapsuleView(
                    timeText: capsuleFormatter.string(from: entry.time),
                    arrowAngle: Angle(radians: arrowAngle + .pi / 2)
                )
                .position(point)
            }
        }
    }

    private func arrowAngleRadians(from point: CGPoint, to target: CGPoint) -> Double {
        Double(atan2(target.y - point.y, target.x - point.x))
    }

    private func angleRadians(degrees: Double) -> Double {
        let normalized = degrees - 90
        return normalized * .pi / 180
    }

    private func radiusForAltitude(_ altitude: Double, min: CGFloat, max: CGFloat) -> CGFloat {
        let clamped = Swift.max(0, Swift.min(90, altitude))
        let ratio = clamped / 90
        return max - CGFloat(ratio) * (max - min)
    }

    private func point(from center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        let cosine = CGFloat(Darwin.cos(angle))
        let sine = CGFloat(Darwin.sin(angle))
        return CGPoint(
            x: center.x + radius * cosine,
            y: center.y + radius * sine
        )
    }
}

private struct SunTimeCapsuleView: View {
    let timeText: String
    let arrowAngle: Angle

    var body: some View {
        VStack(spacing: 4) {
            Text(timeText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.thinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(.yellow.opacity(0.7), lineWidth: 1)
                )

            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.yellow.opacity(0.9))
                .rotationEffect(arrowAngle)
        }
    }
}
