//
//  Models.swift
//  Martini
//
//  Data models for the Martini app
//

import Foundation

// MARK: - Decoding Helpers

@propertyWrapper
struct SafeInt: Codable {
    var wrappedValue: Int

    init(wrappedValue: Int = 0) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let intValue = try? container.decode(Int.self) {
            wrappedValue = intValue
            return
        }

        if let stringValue = try? container.decode(String.self), let intValue = Int(stringValue) {
            wrappedValue = intValue
            return
        }

        wrappedValue = 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

@propertyWrapper
struct SafeOptionalInt: Codable {
    var wrappedValue: Int?

    init(wrappedValue: Int? = nil) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            wrappedValue = nil
            return
        }

        if let intValue = try? container.decode(Int.self) {
            wrappedValue = intValue
            return
        }

        if let stringValue = try? container.decode(String.self), let intValue = Int(stringValue) {
            wrappedValue = intValue
            return
        }

        wrappedValue = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value = wrappedValue {
            try container.encode(value)
        } else {
            try container.encodeNil()
        }
    }
}

@propertyWrapper
struct SafeTags: Codable {
    var wrappedValue: [FrameTag]?

    init(wrappedValue: [FrameTag]? = nil) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            wrappedValue = nil
            return
        }

        if let tagObjects = try? container.decode([FrameTag].self) {
            wrappedValue = tagObjects
            return
        }

        if let tagStrings = try? container.decode([String].self) {
            wrappedValue = tagStrings.map { FrameTag(id: nil, name: $0) }
            return
        }

        wrappedValue = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

// MARK: - Creative Model

struct Creative: Codable, Identifiable {
    let id: String
    let shootId: String
    let title: String
    @SafeInt var order: Int
    @SafeInt var isArchived: Int
    @SafeInt var isLive: Int
    @SafeInt var totalFrames: Int
    @SafeInt var completedFrames: Int
    @SafeInt var remainingFrames: Int
    let primaryFrameId: String?
    let frameFileName: String?
    let frameImage: String?
    let frameBoardType: String?
    let frameStatus: String?
    @SafeOptionalInt var frameNumber: Int?
    let image: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case shootId = "shoot_id"
        case title
        case order
        case isArchived = "is_archived"
        case isLive = "is_live"
        case totalFrames = "total_frames"
        case completedFrames = "completed_frames"
        case remainingFrames = "remaining_frames"
        case primaryFrameId = "primary_frame_id"
        case frameFileName = "frame_file_name"
        case frameImage = "frame_image"
        case frameBoardType = "frame_board_type"
        case frameStatus = "frame_status"
        case frameNumber = "frame_number"
        case image
    }
    
    // Computed property for progress percentage
    var progressPercentage: Double {
        guard totalFrames > 0 else { return 0 }
        return Double(completedFrames) / Double(totalFrames) * 100
    }
}

// MARK: - API Response Models

struct CreativesResponse: Codable {
    let success: Bool
    let creatives: [Creative]
    let error: String?
}

// MARK: - Tag Model

struct FrameTag: Codable, Identifiable {
    let id: String?
    let name: String
}

// MARK: - Frame Model

struct Frame: Codable, Identifiable {
    let id: String
    let creativeId: String
    let creativeTitle: String?
    let creativeColor: String?
    let creativeAspectRatio: String?
    let board: String?
    let boardThumb: String?
    let boardFileName: String?
    let boardFileType: String?
    let boardFileSize: Int?
    let photoboard: String?
    let photoboardThumb: String?
    let photoboardFileName: String?
    let photoboardFileType: String?
    let photoboardFileSize: Int?
    let photoboardCrop: String?
    let preview: String?
    let previewThumb: String?
    let previewFileName: String?
    let previewFileType: String?
    let previewFileSize: Int?
    let previewCrop: String?
    let captureClipId: String?
    let captureClip: String?
    let captureClipThumbnail: String?
    let captureClipFileName: String?
    let captureClipFileType: String?
    let captureClipFileSize: Int?
    let captureClipCrop: String?
    let description: String?
    let caption: String?
    let notes: String?
    let crop: String?
    let status: String?
    let statusUpdated: String?
    let isArchived: Int?
    let createdAt: String?
    let lastUpdated: String?
    let frameOrder: String?
    let frameShootOrder: String?
    @SafeTags var tags: [FrameTag]?

    init(
        id: String,
        creativeId: String,
        creativeTitle: String? = nil,
        creativeColor: String? = nil,
        creativeAspectRatio: String? = nil,
        board: String? = nil,
        boardThumb: String? = nil,
        boardFileName: String? = nil,
        boardFileType: String? = nil,
        boardFileSize: Int? = nil,
        photoboard: String? = nil,
        photoboardThumb: String? = nil,
        photoboardFileName: String? = nil,
        photoboardFileType: String? = nil,
        photoboardFileSize: Int? = nil,
        photoboardCrop: String? = nil,
        preview: String? = nil,
        previewThumb: String? = nil,
        previewFileName: String? = nil,
        previewFileType: String? = nil,
        previewFileSize: Int? = nil,
        previewCrop: String? = nil,
        captureClipId: String? = nil,
        captureClip: String? = nil,
        captureClipThumbnail: String? = nil,
        captureClipFileName: String? = nil,
        captureClipFileType: String? = nil,
        captureClipFileSize: Int? = nil,
        captureClipCrop: String? = nil,
        description: String? = nil,
        caption: String? = nil,
        notes: String? = nil,
        crop: String? = nil,
        status: String? = nil,
        statusUpdated: String? = nil,
        isArchived: Int? = nil,
        createdAt: String? = nil,
        lastUpdated: String? = nil,
        frameOrder: String? = nil,
        frameShootOrder: String? = nil,
        tags: [FrameTag]? = []
    ) {
        self.id = id
        self.creativeId = creativeId
        self.creativeTitle = creativeTitle
        self.creativeColor = creativeColor
        self.creativeAspectRatio = creativeAspectRatio
        self.board = board
        self.boardThumb = boardThumb
        self.boardFileName = boardFileName
        self.boardFileType = boardFileType
        self.boardFileSize = boardFileSize
        self.photoboard = photoboard
        self.photoboardThumb = photoboardThumb
        self.photoboardFileName = photoboardFileName
        self.photoboardFileType = photoboardFileType
        self.photoboardFileSize = photoboardFileSize
        self.photoboardCrop = photoboardCrop
        self.preview = preview
        self.previewThumb = previewThumb
        self.previewFileName = previewFileName
        self.previewFileType = previewFileType
        self.previewFileSize = previewFileSize
        self.previewCrop = previewCrop
        self.captureClipId = captureClipId
        self.captureClip = captureClip
        self.captureClipThumbnail = captureClipThumbnail
        self.captureClipFileName = captureClipFileName
        self.captureClipFileType = captureClipFileType
        self.captureClipFileSize = captureClipFileSize
        self.captureClipCrop = captureClipCrop
        self.description = description
        self.caption = caption
        self.notes = notes
        self.crop = crop
        self.status = status
        self.statusUpdated = statusUpdated
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.lastUpdated = lastUpdated
        self.frameOrder = frameOrder
        self.frameShootOrder = frameShootOrder
        self.tags = tags
    }

    enum CodingKeys: String, CodingKey {
        case id
        case creativeId = "creative_id"
        case creativeTitle = "creative_title"
        case creativeColor = "creative_color"
        case creativeAspectRatio = "creative_aspect_ratio"
        case board
        case boardThumb = "board_thumb"
        case boardFileName = "board_file_name"
        case boardFileType = "board_file_type"
        case boardFileSize = "board_file_size"
        case photoboard
        case photoboardThumb = "photoboard_thumb"
        case photoboardFileName = "photoboard_file_name"
        case photoboardFileType = "photoboard_file_type"
        case photoboardFileSize = "photoboard_file_size"
        case photoboardCrop = "photoboard_crop"
        case preview
        case previewThumb = "preview_thumb"
        case previewFileName = "preview_file_name"
        case previewFileType = "preview_file_type"
        case previewFileSize = "preview_file_size"
        case previewCrop = "preview_crop"
        case captureClipId = "capture_clip_id"
        case captureClip = "capture_clip"
        case captureClipThumbnail = "capture_clip_thumbnail"
        case captureClipFileName = "capture_clip_file_name"
        case captureClipFileType = "capture_clip_file_type"
        case captureClipFileSize = "capture_clip_file_size"
        case captureClipCrop = "capture_clip_crop"
        case description
        case caption
        case notes
        case crop
        case status
        case statusUpdated = "status_updated"
        case isArchived = "is_archived"
        case createdAt = "created_at"
        case lastUpdated = "last_updated"
        case frameOrder = "frame_order"
        case frameShootOrder = "frame_shoot_order"
        case tags
    }

    var frameNumber: Int {
        if let order = frameOrder, let value = Int(order) {
            return value
        }
        if let shootOrder = frameShootOrder, let value = Int(shootOrder) {
            return value
        }
        return 0
    }

    var statusEnum: FrameStatus {
        guard let status else { return .none }
        return FrameStatus(rawValue: status.lowercased()) ?? .none
    }
}

struct FramesResponse: Codable {
    let success: Bool
    let frames: [Frame]
    let error: String?
}
