import CoreLocation
import Foundation
import WeatherKit

struct ScheduleWeatherDisplay: Equatable {
    struct Current: Equatable {
        let temperatureCelsius: Double
        let symbolName: String
    }

    struct Daily: Equatable {
        let highCelsius: Double
        let lowCelsius: Double
        let symbolName: String
    }

    struct HourEntry: Equatable {
        let date: Date
        let temperatureCelsius: Double
        let symbolName: String
    }

    enum Header: Equatable {
        case current(Current)
        case daily(Daily)
    }

    let header: Header?
    let hourly: [HourEntry]
}

enum ScheduleWeatherFormatter {
    private static let temperatureFormatter: MeasurementFormatter = {
        let formatter = MeasurementFormatter()
        formatter.locale = .current
        formatter.unitStyle = .short
        formatter.numberFormatter.maximumFractionDigits = 0
        return formatter
    }()

    static func temperatureText(for celsiusValue: Double) -> String {
        let measurement = Measurement(value: celsiusValue, unit: UnitTemperature.celsius)
        return temperatureFormatter.string(from: measurement)
    }
}

final class ScheduleWeatherService {
    static let shared = ScheduleWeatherService()

    private let weatherService = WeatherService.shared
    private let geocoder = CLGeocoder()
    private let cache = ScheduleWeatherCache.shared

    func weatherDisplay(
        for scheduleDate: Date,
        locationName: String?,
        coordinate: CLLocationCoordinate2D?
    ) async -> ScheduleWeatherDisplay? {
        let calendar = Calendar.current
        let now = Date()
        let scheduleDay = calendar.startOfDay(for: scheduleDate)
        let today = calendar.startOfDay(for: now)
        let tenDaysOut = calendar.date(byAdding: .day, value: 10, to: today)
        guard scheduleDay >= today,
              let tenDaysOut,
              scheduleDay <= tenDaysOut else {
            let tenDaysOutDescription = tenDaysOut.map { "\($0)" } ?? "unknown"
            print("🌦️ Schedule weather skipped: date \(scheduleDay) outside \(today)...\(tenDaysOutDescription)")
            return nil
        }

        guard let resolvedCoordinate = await resolveCoordinate(from: coordinate, locationName: locationName) else {
            print("🌦️ Schedule weather skipped: no coordinate for location \(locationName ?? "unknown")")
            return nil
        }

        let cacheKey = cacheKey(for: resolvedCoordinate)
        var cached = await cache.load(for: cacheKey)
        let wantsCurrent = calendar.isDate(scheduleDay, inSameDayAs: today)
        let wantsHourly = shouldFetchHourly(for: scheduleDay, today: today, now: now, calendar: calendar)
        let wantsDaily = !wantsCurrent

        let needsCurrent = wantsCurrent && !cache.isCurrentFresh(cached)
        let needsHourly = wantsHourly && !cache.isHourlyFresh(cached)
        let needsDaily = wantsDaily && !cache.isDailyFresh(cached, now: now, calendar: calendar)
        let needsFetch = needsCurrent || needsHourly || needsDaily

        if needsFetch {
            do {
                print("🌦️ Fetching weather for \(scheduleDay) at \(resolvedCoordinate.latitude), \(resolvedCoordinate.longitude)")
                let weather = try await weatherService.weather(
                    for: CLLocation(latitude: resolvedCoordinate.latitude, longitude: resolvedCoordinate.longitude)
                )
                let fetchedAt = Date()
                var updated = cached ?? CachedWeatherPayload(coordinate: .init(resolvedCoordinate))
                updated.current = CachedWeatherPayload.Current(
                    temperatureCelsius: weather.currentWeather.temperature.converted(to: .celsius).value,
                    symbolName: weather.currentWeather.symbolName
                )
                updated.hourly = weather.hourlyForecast.forecast.prefix(48).map {
                    CachedWeatherPayload.Hour(
                        date: $0.date,
                        temperatureCelsius: $0.temperature.converted(to: .celsius).value,
                        symbolName: $0.symbolName
                    )
                }
                updated.daily = weather.dailyForecast.forecast.prefix(10).map {
                    CachedWeatherPayload.Day(
                        date: $0.date,
                        highCelsius: $0.highTemperature.converted(to: .celsius).value,
                        lowCelsius: $0.lowTemperature.converted(to: .celsius).value,
                        symbolName: $0.symbolName
                    )
                }
                updated.fetchedAtCurrent = fetchedAt
                updated.fetchedAtHourly = fetchedAt
                updated.fetchedAtDaily = fetchedAt
                await cache.store(updated, for: cacheKey)
                cached = updated
                print("🌦️ Weather cache updated for \(scheduleDay)")
            } catch is CancellationError {
                return await buildDisplay(
                    from: cached,
                    scheduleDay: scheduleDay,
                    wantsCurrent: wantsCurrent,
                    wantsHourly: wantsHourly,
                    calendar: calendar
                )
            } catch {
                let nsError = error as NSError
                let authFailureDomains: Set<String> = [
                    "WeatherDaemon.WDSJWTAuthenticatorServiceProxy.Errors",
                    "WeatherDaemon.WDSJWTAuthenticatorServiceListener.Errors"
                ]
                if authFailureDomains.contains(nsError.domain) {
                    print("🌦️ Weather fetch failed: WeatherKit authentication failed. Check entitlements, bundle ID, and system settings.")
                    print(
                        """
                        🌦️ WeatherKit error details:
                        - domain: \(nsError.domain)
                        - code: \(nsError.code)
                        - description: \(nsError.localizedDescription)
                        - userInfo: \(nsError.userInfo)
                        """
                    )
                } else {
                    print(
                        """
                        🌦️ Weather fetch failed: \(error.localizedDescription)
                        🌦️ WeatherKit error details:
                        - domain: \(nsError.domain)
                        - code: \(nsError.code)
                        - description: \(nsError.localizedDescription)
                        - userInfo: \(nsError.userInfo)
                        """
                    )
                }
                return await buildDisplay(
                    from: cached,
                    scheduleDay: scheduleDay,
                    wantsCurrent: wantsCurrent,
                    wantsHourly: wantsHourly,
                    calendar: calendar
                )
            }
        }

        return await buildDisplay(
            from: cached,
            scheduleDay: scheduleDay,
            wantsCurrent: wantsCurrent,
            wantsHourly: wantsHourly,
            calendar: calendar
        )
    }

    private func buildDisplay(
        from cached: CachedWeatherPayload?,
        scheduleDay: Date,
        wantsCurrent: Bool,
        wantsHourly: Bool,
        calendar: Calendar
    ) async -> ScheduleWeatherDisplay? {
        guard let cached else { return nil }
        let header: ScheduleWeatherDisplay.Header?
        if wantsCurrent, let current = cached.current {
            header = .current(.init(temperatureCelsius: current.temperatureCelsius, symbolName: current.symbolName))
        } else if let daily = cached.daily.first(where: { calendar.isDate($0.date, inSameDayAs: scheduleDay) }) {
            header = .daily(.init(
                highCelsius: daily.highCelsius,
                lowCelsius: daily.lowCelsius,
                symbolName: daily.symbolName
            ))
        } else {
            header = nil
        }

        let hourlyEntries: [ScheduleWeatherDisplay.HourEntry]
        if wantsHourly {
            hourlyEntries = cached.hourly
                .filter { calendar.isDate($0.date, inSameDayAs: scheduleDay) }
                .map { entry in
                    ScheduleWeatherDisplay.HourEntry(
                        date: entry.date,
                        temperatureCelsius: entry.temperatureCelsius,
                        symbolName: entry.symbolName
                    )
                }
        } else {
            hourlyEntries = []
        }

        if header == nil && hourlyEntries.isEmpty {
            return nil
        }

        return ScheduleWeatherDisplay(header: header, hourly: hourlyEntries)
    }

    private func resolveCoordinate(
        from coordinate: CLLocationCoordinate2D?,
        locationName: String?
    ) async -> CLLocationCoordinate2D? {
        if let coordinate {
            return coordinate
        }
        guard let locationName, !locationName.isEmpty else { return nil }
        do {
            let placemarks = try await geocoder.geocodeAddressString(locationName)
            return placemarks.first?.location?.coordinate
        } catch {
            return nil
        }
    }

    private func shouldFetchHourly(
        for scheduleDay: Date,
        today: Date,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard let limit = calendar.date(byAdding: .hour, value: 48, to: now) else { return false }
        return scheduleDay <= limit && scheduleDay >= today
    }

    private func cacheKey(for coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.3f_%.3f", coordinate.latitude, coordinate.longitude)
    }
}

actor ScheduleWeatherCache {
    static let shared = ScheduleWeatherCache()

    private let cacheDirectory: URL

    init() {
        let baseDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        cacheDirectory = baseDirectory.appendingPathComponent("ScheduleWeatherCache", isDirectory: true)
        if !FileManager.default.fileExists(atPath: cacheDirectory.path) {
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }

    func load(for key: String) -> CachedWeatherPayload? {
        let url = cacheDirectory.appendingPathComponent(key).appendingPathExtension("json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CachedWeatherPayload.self, from: data)
    }

    func store(_ payload: CachedWeatherPayload, for key: String) {
        let url = cacheDirectory.appendingPathComponent(key).appendingPathExtension("json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    nonisolated func isCurrentFresh(_ payload: CachedWeatherPayload?, now: Date = Date()) -> Bool {
        guard let fetchedAt = payload?.fetchedAtCurrent else { return false }
        return now.timeIntervalSince(fetchedAt) < 15 * 60
    }

    nonisolated func isHourlyFresh(_ payload: CachedWeatherPayload?, now: Date = Date()) -> Bool {
        guard let fetchedAt = payload?.fetchedAtHourly else { return false }
        return now.timeIntervalSince(fetchedAt) < 60 * 60
    }

    nonisolated func isDailyFresh(_ payload: CachedWeatherPayload?, now: Date, calendar: Calendar) -> Bool {
        guard let fetchedAt = payload?.fetchedAtDaily else { return false }
        let nextRefresh = nextDailyRefreshDate(after: fetchedAt, calendar: calendar)
        return now < nextRefresh
    }

    private nonisolated func nextDailyRefreshDate(after date: Date, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = 6
        components.minute = 0
        components.second = 0
        let todayRefresh = calendar.date(from: components) ?? date
        if date < todayRefresh {
            return todayRefresh
        }
        return calendar.date(byAdding: .day, value: 1, to: todayRefresh) ?? todayRefresh
    }
}

struct CachedWeatherPayload: Codable {
    struct Coordinate: Codable {
        let latitude: Double
        let longitude: Double

        init(_ coordinate: CLLocationCoordinate2D) {
            latitude = coordinate.latitude
            longitude = coordinate.longitude
        }
    }

    struct Current: Codable {
        let temperatureCelsius: Double
        let symbolName: String
    }

    struct Hour: Codable {
        let date: Date
        let temperatureCelsius: Double
        let symbolName: String
    }

    struct Day: Codable {
        let date: Date
        let highCelsius: Double
        let lowCelsius: Double
        let symbolName: String
    }

    let coordinate: Coordinate
    var current: Current?
    var hourly: [Hour]
    var daily: [Day]
    var fetchedAtCurrent: Date?
    var fetchedAtHourly: Date?
    var fetchedAtDaily: Date?

    init(coordinate: Coordinate) {
        self.coordinate = coordinate
        current = nil
        hourly = []
        daily = []
        fetchedAtCurrent = nil
        fetchedAtHourly = nil
        fetchedAtDaily = nil
    }
}
