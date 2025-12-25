import Foundation

struct PackPayload: Codable {
    let dbVersion: String
    let pack: PackInfo
    let cameras: [PackCamera]
    let lensPacks: [PackLensPack]
    let lenses: [PackLens]
    let lensPackItems: [PackLensPackItem]

    enum CodingKeys: String, CodingKey {
        case dbVersion = "db_version"
        case pack
        case cameras
        case lensPacks = "lens_packs"
        case lenses
        case lensPackItems = "lens_pack_items"
    }
}

struct PackInfo: Codable {
    let packId: String
    let revision: Int
    let createdAt: String
    let description: String

    enum CodingKeys: String, CodingKey {
        case packId = "pack_id"
        case revision
        case createdAt = "created_at"
        case description
    }
}

struct PackCamera: Codable {
    let id: String
    let brand: String
    let model: String
    let sensorType: String?
    let mount: String?
    let modes: [PackCameraMode]

    enum CodingKeys: String, CodingKey {
        case id
        case brand
        case model
        case sensorType = "sensor_type"
        case mount
        case modes
    }
}

struct PackCameraMode: Codable {
    let id: String
    let name: String
    let sensorWidthMm: Double
    let sensorHeightMm: Double
    let resolution: String?
    let aspectRatio: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case sensorWidthMm = "sensor_width_mm"
        case sensorHeightMm = "sensor_height_mm"
        case resolution
        case aspectRatio = "aspect_ratio"
    }
}

struct PackLensPack: Codable {
    let id: String
    let brand: String
    let name: String
    let type: String
    let format: String
    let description: String
}

struct PackLensPackItem: Codable {
    let packId: String
    let lensId: String
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case packId = "pack_id"
        case lensId = "lens_id"
        case sortOrder = "sort_order"
    }
}

struct PackLens: Codable {
    let id: String?
    let type: String
    let brand: String
    let series: String
    let format: String?
    let mounts: [String]?
    let focalLengthMm: Double?
    let focalLengthMmMin: Double?
    let focalLengthMmMax: Double?
    let maxTStop: Double
    let squeeze: Double

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case brand
        case series
        case format
        case mounts
        case focalLengthMm = "focal_length_mm"
        case focalLengthMmMin = "focal_length_mm_min"
        case focalLengthMmMax = "focal_length_mm_max"
        case maxTStop = "max_t_stop"
        case squeeze
    }
}
