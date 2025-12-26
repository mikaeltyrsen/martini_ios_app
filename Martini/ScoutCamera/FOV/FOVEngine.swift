import Foundation

struct FOVMatchResult: Equatable {
    let cameraRole: String
    let zoomFactor: Double
    let errorRadians: Double
}

struct FOVEngine {
    static func matchIPhoneModule(
        targetHFOVRadians: Double,
        iphoneCameras: [DBIPhoneCamera],
        calibrationMultipliers: [String: Double]
    ) -> FOVMatchResult? {
        var best: FOVMatchResult?

        for camera in iphoneCameras {
            let calibratedHFOVDegrees = calibratedHFOVDegrees(camera: camera, calibrationMultipliers: calibrationMultipliers)
            let nativeHFOV = FOVMath.degreesToRadians(calibratedHFOVDegrees)
            guard targetHFOVRadians > 0 else { continue }
            let requiredZoom = nativeHFOV / targetHFOVRadians
            let zoom = min(max(requiredZoom, camera.minZoom), camera.maxZoom)
            let adjustedHFOV = nativeHFOV / zoom
            let error = abs(adjustedHFOV - targetHFOVRadians)
            let result = FOVMatchResult(cameraRole: camera.cameraRole, zoomFactor: zoom, errorRadians: error)

            if let current = best {
                if result.errorRadians < current.errorRadians {
                    best = result
                }
            } else {
                best = result
            }
        }

        return best
    }

    static func calibratedHFOVDegrees(
        camera: DBIPhoneCamera,
        calibrationMultipliers: [String: Double]
    ) -> Double {
        let multiplier = calibrationMultipliers[camera.cameraRole] ?? 1.0
        return camera.nativeHFOVDegrees * multiplier
    }
}
