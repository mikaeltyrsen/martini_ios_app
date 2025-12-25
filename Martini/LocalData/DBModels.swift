import Foundation

struct DBPack: Identifiable, Hashable {
    let id: String
    let name: String
    let revision: Int
}

struct DBCamera: Identifiable, Hashable {
    let id: String
    let brand: String
    let model: String
    let sensorType: String?
    let mount: String?
    let sensorWidthMm: Double?
    let sensorHeightMm: Double?
}

struct DBCameraMode: Identifiable, Hashable {
    let id: String
    let cameraId: String
    let name: String
    let sensorWidthMm: Double
    let sensorHeightMm: Double
    let resolution: String?
    let aspectRatio: String?
}

struct DBLens: Identifiable, Hashable {
    let id: String
    let type: String
    let brand: String
    let series: String
    let format: String?
    let mounts: [String]
    let focalLengthMm: Double?
    let focalLengthMinMm: Double?
    let focalLengthMaxMm: Double?
    let maxTStop: Double
    let squeeze: Double

    var isZoom: Bool {
        focalLengthMinMm != nil && focalLengthMaxMm != nil
    }
}

struct DBLensUserPreference: Identifiable, Hashable {
    let lensId: String
    let isFavorite: Bool
    let userLabel: String?
    let isHidden: Bool
    let lastUsedAt: String?

    var id: String { lensId }
}

struct DBIPhoneCamera: Identifiable, Hashable {
    let id: String
    let iphoneModel: String
    let cameraRole: String
    let nativeHFOVDegrees: Double
    let minZoom: Double
    let maxZoom: Double
}

struct DBProjectCamera: Identifiable, Hashable {
    let id: String
    let projectId: String
    let cameraId: String
}

struct DBProjectLens: Identifiable, Hashable {
    let id: String
    let projectId: String
    let lensId: String
}
