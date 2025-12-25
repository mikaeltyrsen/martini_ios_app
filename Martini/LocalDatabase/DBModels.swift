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
    let sensorWidthMm: Double
    let sensorHeightMm: Double
}

struct DBCameraMode: Identifiable, Hashable {
    let id: String
    let cameraId: String
    let name: String
    let sensorWidthMm: Double
    let sensorHeightMm: Double
}

struct DBLens: Identifiable, Hashable {
    let id: String
    let brand: String
    let series: String
    let focalLengthMinMm: Double
    let focalLengthMaxMm: Double
    let tStop: Double
    let squeeze: Double
    let isZoom: Bool
}

struct DBLensUserPreference: Identifiable, Hashable {
    let id: String
    let lensId: String
    let isFavorite: Bool
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
