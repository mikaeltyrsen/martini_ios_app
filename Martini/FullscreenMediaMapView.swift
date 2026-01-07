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
    @State private var mapStyleOption: MapStyleOption = .satellite
    @State private var mapHeadingDegrees: Double = 0

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
                mapStylePicker
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
            Annotation("", coordinate: coordinate) {
                ScoutMapOverlayView(
                    headingDegrees: headingDegrees ?? 0,
                    mapHeadingDegrees: mapHeadingDegrees,
                    fovDegrees: fovDegrees,
                    sunPath: sunData?.path ?? [],
                    capsuleEntries: capsuleEntries
                )
                .allowsHitTesting(false)
            }
        }
        .mapStyle(mapStyleOption.mapStyle)
        .frame(maxWidth: .infinity, minHeight: 320)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onMapCameraChange(frequency: .continuous) { context in
            mapHeadingDegrees = context.camera.heading
        }
        .overlay(alignment: .bottomTrailing) {
            locateCameraButton
                .padding(12)
        }
    }

    private var mapStylePicker: some View {
        Picker("Map Style", selection: $mapStyleOption) {
            ForEach(MapStyleOption.allCases) { option in
                Text(option.title)
                    .tag(option)
            }
        }
        .pickerStyle(.segmented)
    }

    private var locateCameraButton: some View {
        Button(action: recenterCamera) {
            Image(systemName: "scope")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .background(.thinMaterial, in: Circle())
        .overlay(
            Circle()
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
        .accessibilityLabel("Center on camera")
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
        return limitedCapsuleEntries(from: entries, maxCount: 7)
    }

    private func limitedCapsuleEntries(from entries: [SunPathEntry], maxCount: Int) -> [SunPathEntry] {
        guard entries.count > maxCount, maxCount > 1 else { return entries }
        let step = Double(entries.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { index in
            let position = Int(round(Double(index) * step))
            return entries[min(position, entries.count - 1)]
        }
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

    private func recenterCamera() {
        let camera = MapCamera(
            centerCoordinate: coordinate,
            distance: 180,
            heading: 0,
            pitch: 0
        )
        withAnimation {
            cameraPosition = .camera(camera)
        }
    }
}

private enum MapStyleOption: String, CaseIterable, Identifiable {
    case satellite
    case standard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .satellite:
            return "Satellite"
        case .standard:
            return "Map"
        }
    }

    var mapStyle: MapStyle {
        switch self {
        case .satellite:
            return .imagery(elevation: .realistic)
        case .standard:
            return .standard
        }
    }
}

private struct ScoutMapOverlayView: View {
    let headingDegrees: Double
    let mapHeadingDegrees: Double
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
            let fovLineColor = Color.yellow.opacity(0.9)
            let shadowColor = Color.black.opacity(0.35)

            Path { path in
                path.move(to: center)
                path.addLine(to: point(from: center, radius: radius, angle: leftAngle))
                path.addArc(
                    center: center,
                    radius: radius,
                    startAngle: Angle(radians: leftAngle),
                    endAngle: Angle(radians: rightAngle),
                    clockwise: false
                )
                path.closeSubpath()
            }
            .fill(Color.white.opacity(0.5))
            .shadow(color: shadowColor, radius: 3, x: 0, y: 2)

            Path { path in
                path.move(to: center)
                path.addLine(to: point(from: center, radius: radius, angle: leftAngle))
                path.move(to: center)
                path.addLine(to: point(from: center, radius: radius, angle: rightAngle))
            }
            .stroke(fovLineColor, lineWidth: 2)
            .shadow(color: shadowColor, radius: 2, x: 0, y: 1)

            Path { path in
                path.move(to: point(from: center, radius: radius, angle: leftAngle))
                path.addArc(
                    center: center,
                    radius: radius,
                    startAngle: Angle(radians: leftAngle),
                    endAngle: Angle(radians: rightAngle),
                    clockwise: false
                )
            }
            .stroke(fovLineColor.opacity(0.8), lineWidth: 2)
            .shadow(color: shadowColor, radius: 2, x: 0, y: 1)

            Circle()
                .fill(Color.black)
                .frame(width: 6, height: 6)
                .position(center)
                .shadow(color: shadowColor, radius: 2, x: 0, y: 1)
        }
    }

    private var sunPathOverlay: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let maxRadius = min(proxy.size.width, proxy.size.height) * 0.54
            let minRadius = min(proxy.size.width, proxy.size.height) * 0.2
            let sunPoints = sunPath.map { entry in
                let radius = radiusForAltitude(entry.altitudeDegrees, min: minRadius, max: maxRadius)
                let angle = angleRadians(degrees: entry.azimuthDegrees)
                return point(from: center, radius: radius, angle: angle)
            }
            smoothedPath(points: sunPoints)
                .stroke(.yellow.opacity(0.85), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)

            ForEach(Array(capsuleEntries.enumerated()), id: \.offset) { _, entry in
                let radius = radiusForAltitude(entry.altitudeDegrees, min: minRadius, max: maxRadius)
                let angle = angleRadians(degrees: entry.azimuthDegrees)
                let point = point(from: center, radius: radius, angle: angle)
                let arrowAngle = arrowAngleRadians(from: point, to: center)
                let direction = unitVector(from: point, to: center)
                let labelOffset = CGSize(width: -direction.x * 18, height: -direction.y * 18)
                let dotSize: CGFloat = 6

                Circle()
                    .fill(Color.white)
                    .frame(width: dotSize, height: dotSize)
                    .position(point)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)

                SunDirectionArrowView(
                    angle: Angle(radians: arrowAngle + .pi / 2),
                    length: 16,
                    stemLength: 6
                )
                .position(point)

                SunTimeCapsuleView(
                    timeText: capsuleFormatter.string(from: entry.time)
                )
                .position(point)
                .offset(labelOffset)
            }
        }
    }

    private func arrowAngleRadians(from point: CGPoint, to target: CGPoint) -> Double {
        Double(atan2(target.y - point.y, target.x - point.x))
    }

    private func angleRadians(degrees: Double) -> Double {
        let adjusted = degrees - mapHeadingDegrees
        let normalized = adjusted - 90
        return normalized * .pi / 180
    }

    private func smoothedPath(points: [CGPoint]) -> Path {
        var path = Path()
        guard points.count > 1 else {
            if let point = points.first {
                path.move(to: point)
            }
            return path
        }

        path.move(to: points[0])
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let midpoint = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
            path.addQuadCurve(to: midpoint, control: previous)
        }
        if let last = points.last, let secondLast = points.dropLast().last {
            path.addQuadCurve(to: last, control: secondLast)
        }
        return path
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

    private func unitVector(from point: CGPoint, to target: CGPoint) -> CGPoint {
        let dx = target.x - point.x
        let dy = target.y - point.y
        let length = max(0.001, sqrt(dx * dx + dy * dy))
        return CGPoint(x: dx / length, y: dy / length)
    }
}

private struct SunTimeCapsuleView: View {
    let timeText: String

    var body: some View {
        VStack(spacing: 4) {
            Text(timeText)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.thinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(.yellow.opacity(0.7), lineWidth: 1)
                )
        }
    }
}

private struct SunDirectionArrowView: View {
    let angle: Angle
    let length: CGFloat
    let stemLength: CGFloat

    var body: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 0, y: stemLength))
                path.addLine(to: CGPoint(x: 0, y: -length))
            }
            .stroke(.yellow.opacity(0.9), lineWidth: 1.5)

            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.yellow.opacity(0.9))
                .offset(y: -length)
        }
        .rotationEffect(angle)
        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
    }
}
