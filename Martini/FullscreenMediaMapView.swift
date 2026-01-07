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
        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)
        )
        _cameraPosition = State(initialValue: .region(region))
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
        Map(position: $cameraPosition) {
            Annotation("Scout", coordinate: coordinate) {
                ScoutMapOverlayView(
                    headingDegrees: headingDegrees ?? 0,
                    fovDegrees: fovDegrees,
                    sunPath: sunData?.path ?? [],
                    sunrise: sunData?.sunrise,
                    sunset: sunData?.sunset
                )
            }
        }
        .mapStyle(.imagery(elevation: .realistic))
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
    let sunrise: Date?
    let sunset: Date?

    private let overlaySize: CGFloat = 260

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

            if let sunrisePoint = sunEventPoint(center: center, minRadius: minRadius, maxRadius: maxRadius, isSunrise: true),
               let sunsetPoint = sunEventPoint(center: center, minRadius: minRadius, maxRadius: maxRadius, isSunrise: false) {
                Circle()
                    .fill(.orange)
                    .frame(width: 8, height: 8)
                    .position(sunrisePoint)
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .position(sunsetPoint)
            }
        }
    }

    private func sunEventPoint(center: CGPoint, minRadius: CGFloat, maxRadius: CGFloat, isSunrise: Bool) -> CGPoint? {
        guard let event = isSunrise ? sunPath.first : sunPath.last else { return nil }
        let radius = radiusForAltitude(event.altitudeDegrees, min: minRadius, max: maxRadius)
        let angle = angleRadians(degrees: event.azimuthDegrees)
        return point(from: center, radius: radius, angle: angle)
    }

    private func angleRadians(degrees: Double) -> Double {
        let normalized = degrees - 90
        return normalized * .pi / 180
    }

    private func radiusForAltitude(_ altitude: Double, min: CGFloat, max: CGFloat) -> CGFloat {
        let clamped = max(0, min(90, altitude))
        let ratio = clamped / 90
        return max - CGFloat(ratio) * (max - min)
    }

    private func point(from center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        CGPoint(
            x: center.x + radius * cos(angle),
            y: center.y + radius * sin(angle)
        )
    }
}
