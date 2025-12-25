import Foundation

struct LensIdBuilder {
    static func buildId(brand: String, series: String, focal: String, tStop: Double, squeeze: Double) -> String {
        let cleanedBrand = sanitize(brand)
        let cleanedSeries = sanitize(series)
        let cleanedFocal = sanitize(focal)
        let tStopValue = String(format: "t%.1f", tStop).replacingOccurrences(of: ".", with: "_")
        let squeezeValue = String(format: "%.1fx", squeeze).replacingOccurrences(of: ".", with: "_")
        return "\(cleanedBrand)_\(cleanedSeries)__\(cleanedFocal)__\(tStopValue)__\(squeezeValue)"
    }

    private static func sanitize(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "-", with: "-")
    }
}
