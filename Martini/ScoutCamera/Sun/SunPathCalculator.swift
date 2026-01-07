import CoreLocation
import Foundation

struct SunPathEntry {
    let time: Date
    let azimuthDegrees: Double
    let altitudeDegrees: Double
}

struct SunData {
    let sunrise: Date
    let sunset: Date
    let solarNoon: Date
    let path: [SunPathEntry]
}

struct SunPathCalculator {
    private let rad = Double.pi / 180
    private let daySeconds: Double = 86400
    private let julian1970: Double = 2440588
    private let julian2000: Double = 2451545
    private let obliquity: Double = 23.4397 * Double.pi / 180

    func sunData(for location: CLLocation, date: Date, timeZone: TimeZone) -> SunData? {
        let dayStart = startOfDay(for: date, timeZone: timeZone)
        let times = sunTimes(for: location.coordinate, date: dayStart)
        guard let sunrise = times.sunrise, let sunset = times.sunset, let solarNoon = times.solarNoon else {
            return nil
        }

        let path = sunPath(
            coordinate: location.coordinate,
            from: sunrise,
            to: sunset,
            intervalMinutes: 30
        )

        return SunData(sunrise: sunrise, sunset: sunset, solarNoon: solarNoon, path: path)
    }

    func sunPosition(for coordinate: CLLocationCoordinate2D, date: Date) -> SunPathEntry {
        let lw = -coordinate.longitude * rad
        let phi = coordinate.latitude * rad
        let d = toDays(date)
        let c = sunCoordinates(d)
        let h = siderealTime(d, lw) - c.rightAscension
        let azimuth = azimuth(hourAngle: h, latitude: phi, declination: c.declination)
        let altitude = altitude(hourAngle: h, latitude: phi, declination: c.declination)
        return SunPathEntry(
            time: date,
            azimuthDegrees: azimuth / rad + 180,
            altitudeDegrees: altitude / rad
        )
    }

    private func sunTimes(for coordinate: CLLocationCoordinate2D, date: Date) -> (sunrise: Date?, sunset: Date?, solarNoon: Date?) {
        let lw = -coordinate.longitude * rad
        let phi = coordinate.latitude * rad
        let d = toDays(date)

        let n = julianCycle(d, lw)
        let ds = approxTransit(approximateJulianCycle: n, longitude: lw)
        let m = solarMeanAnomaly(ds)
        let l = eclipticLongitude(m)
        let dec = declination(l)

        let jnoon = solarTransit(ds, meanAnomaly: m, eclipticLongitude: l)
        let h0 = -0.833 * rad
        let w0 = hourAngle(altitude: h0, latitude: phi, declination: dec)

        guard !w0.isNaN else {
            return (nil, nil, nil)
        }

        let jset = julian2000 + (w0 + lw) / (2 * Double.pi) + n + 0.0053 * sin(m) - 0.0069 * sin(2 * l)
        let jrise = jnoon - (jset - jnoon)

        return (
            fromJulian(jrise),
            fromJulian(jset),
            fromJulian(jnoon)
        )
    }

    private func sunPath(coordinate: CLLocationCoordinate2D, from: Date, to: Date, intervalMinutes: Int) -> [SunPathEntry] {
        guard from < to else { return [] }
        let interval = TimeInterval(intervalMinutes * 60)
        var entries: [SunPathEntry] = []
        var current = from
        while current <= to {
            entries.append(sunPosition(for: coordinate, date: current))
            current = current.addingTimeInterval(interval)
        }
        if entries.last?.time != to {
            entries.append(sunPosition(for: coordinate, date: to))
        }
        return entries
    }

    private func startOfDay(for date: Date, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.startOfDay(for: date)
    }

    private func toJulian(_ date: Date) -> Double {
        date.timeIntervalSince1970 / daySeconds + julian1970
    }

    private func fromJulian(_ julian: Double) -> Date {
        Date(timeIntervalSince1970: (julian - julian1970) * daySeconds)
    }

    private func toDays(_ date: Date) -> Double {
        toJulian(date) - julian2000
    }

    private func rightAscension(_ l: Double) -> Double {
        atan2(sin(l) * cos(obliquity), cos(l))
    }

    private func declination(_ l: Double) -> Double {
        asin(sin(obliquity) * sin(l))
    }

    private func azimuth(hourAngle: Double, latitude: Double, declination: Double) -> Double {
        atan2(
            sin(hourAngle),
            cos(hourAngle) * sin(latitude) - tan(declination) * cos(latitude)
        )
    }

    private func altitude(hourAngle: Double, latitude: Double, declination: Double) -> Double {
        asin(sin(latitude) * sin(declination) + cos(latitude) * cos(declination) * cos(hourAngle))
    }

    private func siderealTime(_ d: Double, _ lw: Double) -> Double {
        rad * (280.16 + 360.9856235 * d) - lw
    }

    private func solarMeanAnomaly(_ d: Double) -> Double {
        rad * (357.5291 + 0.98560028 * d)
    }

    private func eclipticLongitude(_ m: Double) -> Double {
        let c = rad * (1.9148 * sin(m) + 0.02 * sin(2 * m) + 0.0003 * sin(3 * m))
        let p = rad * 102.9372
        return m + c + p + Double.pi
    }

    private func julianCycle(_ d: Double, _ lw: Double) -> Double {
        let j0 = 0.0009
        return round(d - j0 - lw / (2 * Double.pi))
    }

    private func approxTransit(approximateJulianCycle n: Double, longitude lw: Double) -> Double {
        let j0 = 0.0009
        return j0 + (lw / (2 * Double.pi)) + n
    }

    private func solarTransit(_ ds: Double, meanAnomaly m: Double, eclipticLongitude l: Double) -> Double {
        julian2000 + ds + 0.0053 * sin(m) - 0.0069 * sin(2 * l)
    }

    private func hourAngle(altitude h0: Double, latitude phi: Double, declination dec: Double) -> Double {
        acos((sin(h0) - sin(phi) * sin(dec)) / (cos(phi) * cos(dec)))
    }

    private func sunCoordinates(_ d: Double) -> (declination: Double, rightAscension: Double) {
        let m = solarMeanAnomaly(d)
        let l = eclipticLongitude(m)
        return (declination(l), rightAscension(l))
    }
}
