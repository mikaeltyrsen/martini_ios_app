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
struct SafeBool: Codable {
    var wrappedValue: Bool

    init(wrappedValue: Bool = false) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let boolValue = try? container.decode(Bool.self) {
            wrappedValue = boolValue
            return
        }

        if let intValue = try? container.decode(Int.self) {
            wrappedValue = intValue != 0
            return
        }

        if let stringValue = try? container.decode(String.self) {
            let lowercased = stringValue.lowercased()
            if ["true", "1", "yes"].contains(lowercased) {
                wrappedValue = true
                return
            }
            if ["false", "0", "no"].contains(lowercased) {
                wrappedValue = false
                return
            }
        }

        wrappedValue = false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

@propertyWrapper
struct SafeOptionalBool: Codable {
    var wrappedValue: Bool?

    init(wrappedValue: Bool? = nil) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            wrappedValue = nil
            return
        }

        if let boolValue = try? container.decode(Bool.self) {
            wrappedValue = boolValue
            return
        }

        if let intValue = try? container.decode(Int.self) {
            wrappedValue = intValue != 0
            return
        }

        if let stringValue = try? container.decode(String.self) {
            let lowercased = stringValue.lowercased()
            if ["true", "1", "yes"].contains(lowercased) {
                wrappedValue = true
                return
            }
            if ["false", "0", "no"].contains(lowercased) {
                wrappedValue = false
                return
            }
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
    let shootId: String?
    let title: String
    @SafeInt var order: Int
    @SafeBool var isArchived: Bool
    @SafeBool var isLive: Bool
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
    @SafeBool var success: Bool
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
    @SafeOptionalInt var boardFileSize: Int?
    let photoboard: String?
    let photoboardThumb: String?
    let photoboardFileName: String?
    let photoboardFileType: String?
    @SafeOptionalInt var photoboardFileSize: Int?
    let photoboardCrop: String?
    let preview: String?
    let previewThumb: String?
    let previewFileName: String?
    let previewFileType: String?
    @SafeOptionalInt var previewFileSize: Int?
    let previewCrop: String?
    let captureClipId: String?
    let captureClip: String?
    let captureClipThumbnail: String?
    let captureClipFileName: String?
    let captureClipFileType: String?
    @SafeOptionalInt var captureClipFileSize: Int?
    let captureClipCrop: String?
    let description: String?
    let caption: String?
    let notes: String?
    let crop: String?
    let status: String?
    let statusUpdated: String?
    @SafeOptionalBool var isArchived: Bool?
    let createdAt: String?
    let lastUpdated: String?
    let frameOrder: String?
    let frameShootOrder: String?
    let schedule: String?
    let frameStartTime: String?
    @SafeOptionalBool var frameHide: Bool?
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
        isArchived: Bool? = nil,
        createdAt: String? = nil,
        lastUpdated: String? = nil,
        frameOrder: String? = nil,
        frameShootOrder: String? = nil,
        schedule: String? = nil,
        frameStartTime: String? = nil,
        frameHide: Bool? = nil,
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
        self.schedule = schedule
        self.frameStartTime = frameStartTime
        self.frameHide = frameHide
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
        case schedule
        case frameStartTime = "frame_start_time"
        case frameHide = "frame_hide"
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

    /// Returns the available assets for this frame in the order they should be shown by default.
    var availableAssets: [FrameAssetItem] {
        var items: [FrameAssetItem] = []

        if board != nil || boardThumb != nil {
            items.append(
                FrameAssetItem(
                    kind: .board,
                    primary: board,
                    fallback: boardThumb,
                    fileType: boardFileType
                )
            )
        }

        if photoboard != nil || photoboardThumb != nil {
            items.append(
                FrameAssetItem(
                    kind: .photoboard,
                    primary: photoboard,
                    fallback: photoboardThumb,
                    fileType: photoboardFileType
                )
            )
        }

        if preview != nil || previewThumb != nil {
            items.append(
                FrameAssetItem(
                    kind: .preview,
                    primary: preview,
                    fallback: previewThumb,
                    fileType: previewFileType
                )
            )
        } else if captureClipThumbnail != nil || captureClip != nil {
            items.append(
                FrameAssetItem(
                    kind: .preview,
                    primary: captureClip,
                    fallback: captureClipThumbnail,
                    fileType: captureClipFileType
                )
            )
        }

        return items
    }

    var isHidden: Bool { frameHide ?? false }

    var formattedStartTime: String? {
        guard let frameStartTime, !frameStartTime.isEmpty else { return nil }
        if let date = Frame.startTimeParser.date(from: frameStartTime) {
            return Frame.startTimeFormatter.string(from: date)
        }
        return frameStartTime
    }

    var hasScheduledTime: Bool { formattedStartTime != nil }

    func updatingStatus(_ status: FrameStatus) -> Frame {
        Frame(
            id: id,
            creativeId: creativeId,
            creativeTitle: creativeTitle,
            creativeColor: creativeColor,
            creativeAspectRatio: creativeAspectRatio,
            board: board,
            boardThumb: boardThumb,
            boardFileName: boardFileName,
            boardFileType: boardFileType,
            boardFileSize: boardFileSize,
            photoboard: photoboard,
            photoboardThumb: photoboardThumb,
            photoboardFileName: photoboardFileName,
            photoboardFileType: photoboardFileType,
            photoboardFileSize: photoboardFileSize,
            photoboardCrop: photoboardCrop,
            preview: preview,
            previewThumb: previewThumb,
            previewFileName: previewFileName,
            previewFileType: previewFileType,
            previewFileSize: previewFileSize,
            previewCrop: previewCrop,
            captureClipId: captureClipId,
            captureClip: captureClip,
            captureClipThumbnail: captureClipThumbnail,
            captureClipFileName: captureClipFileName,
            captureClipFileType: captureClipFileType,
            captureClipFileSize: captureClipFileSize,
            captureClipCrop: captureClipCrop,
            description: description,
            caption: caption,
            notes: notes,
            crop: crop,
            status: status == .none ? nil : status.rawValue,
            statusUpdated: statusUpdated,
            isArchived: isArchived,
            createdAt: createdAt,
            lastUpdated: lastUpdated,
            frameOrder: frameOrder,
            frameShootOrder: frameShootOrder,
            schedule: schedule,
            frameStartTime: frameStartTime,
            frameHide: frameHide,
            tags: tags
        )
    }

    private static let startTimeParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let startTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
}

struct FramesResponse: Codable {
    @SafeBool var success: Bool
    let frames: [Frame]
    let error: String?
}

// MARK: - Frame Assets

enum FrameAssetKind: String, CaseIterable, Hashable {
    case board
    case photoboard
    case preview

    var displayName: String {
        switch self {
        case .board:
            return "Board"
        case .photoboard:
            return "Photoboard"
        case .preview:
            return "Preview"
        }
    }

    var systemImageName: String {
        switch self {
        case .board:
            return "square.on.square"
        case .photoboard:
            return "photo.on.rectangle"
        case .preview:
            return "video"
        }
    }
}

struct FrameAssetItem: Identifiable, Hashable {
    let id = UUID()
    let kind: FrameAssetKind
    private let primary: String?
    private let fallback: String?
    private let fileType: String?

    init(kind: FrameAssetKind, primary: String?, fallback: String?, fileType: String? = nil) {
        self.kind = kind
        self.primary = primary
        self.fallback = fallback
        self.fileType = fileType
    }

    var url: URL? {
        if let primary, let url = URL(string: primary) { return url }
        if let fallback, let url = URL(string: fallback) { return url }
        return nil
    }

    var isVideo: Bool {
        if let fileType, fileType.lowercased().contains("video") { return true }
        guard let url else { return false }
        return Self.videoExtensions.contains(url.pathExtension.lowercased()) || url.absoluteString.lowercased().contains(".m3u8")
    }

    var label: String { kind.displayName }
    var iconName: String { kind.systemImageName }

    private static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "webm", "mkv"]
}
