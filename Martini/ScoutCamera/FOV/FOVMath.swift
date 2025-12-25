import Foundation

enum FOVMath {
    static func horizontalFOV(sensorWidthMm: Double, focalLengthMm: Double, squeeze: Double) -> Double {
        2.0 * atan((sensorWidthMm * squeeze) / (2.0 * focalLengthMm))
    }

    static func verticalFOV(sensorHeightMm: Double, focalLengthMm: Double) -> Double {
        2.0 * atan(sensorHeightMm / (2.0 * focalLengthMm))
    }

    static func radiansToDegrees(_ radians: Double) -> Double {
        radians * 180.0 / .pi
    }

    static func degreesToRadians(_ degrees: Double) -> Double {
        degrees * .pi / 180.0
    }
}
