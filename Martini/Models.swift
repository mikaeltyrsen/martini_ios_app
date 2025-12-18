//
//  Models.swift
//  Martini
//
//  Data models for the Martini app
//

import Foundation

// MARK: - Decoding Helpers

@propertyWrapper
struct SafeInt: Codable, Equatable, Hashable {
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
struct SafeOptionalInt: Codable, Equatable, Hashable {
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
struct SafeBool: Codable, Equatable, Hashable {
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

// MARK: - Project Model

struct ProjectDetails: Codable {
    @SafeBool var success: Bool
    let id: String
    let name: String
    let publishedCreatives: [ProjectCreative]?
    let activeSchedule: ProjectSchedule?

    enum CodingKeys: String, CodingKey {
        case success
        case id
        case name
        case publishedCreatives = "published_creatives"
        case activeSchedule = "active_schedule"
    }
}

struct ProjectCreative: Codable, Identifiable {
    let id: String
    let name: String
}

struct ProjectSchedule: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let schedules: [ProjectScheduleItem]?
    let date: String?
    let title: String?
    let startTime: String?
    let durationMinutes: Int?
    let location: String?
    let lat: Double?
    let lng: Double?
    let groups: [ScheduleGroup]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case schedules
        case schedule
        case date
        case title
        case startTime
        case start_time
        case durationMinutes
        case duration_minutes
        case location
        case lat
        case lng
        case groups
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)

        let resolvedName = try container.decodeIfPresent(String.self, forKey: .name)
        let resolvedTitle = try container.decodeIfPresent(String.self, forKey: .title)
        name = resolvedName ?? resolvedTitle ?? "Schedule"
        title = resolvedTitle ?? resolvedName

        if let directSchedules = try container.decodeIfPresent([ProjectScheduleItem].self, forKey: .schedules) {
            schedules = directSchedules
        } else if let scheduleString = try container.decodeIfPresent(String.self, forKey: .schedule) {
            schedules = ProjectSchedule.decodeEmbeddedSchedules(from: scheduleString)
        } else {
            schedules = nil
        }
        date = try container.decodeIfPresent(String.self, forKey: .date)
        startTime = try container.decodeIfPresent(String.self, forKey: .startTime)
            ?? container.decodeIfPresent(String.self, forKey: .start_time)
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes)
            ?? container.decodeIfPresent(Int.self, forKey: .duration_minutes)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        lat = try container.decodeIfPresent(Double.self, forKey: .lat)
        lng = try container.decodeIfPresent(Double.self, forKey: .lng)
        var decodedGroups = try container.decodeIfPresent([ScheduleGroup].self, forKey: .groups)

        if decodedGroups == nil,
           let schedules,
           schedules.count == 1,
           let scheduleGroups = schedules.first?.groups,
           !scheduleGroups.isEmpty {
            decodedGroups = scheduleGroups
        }

        groups = decodedGroups
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(schedules, forKey: .schedules)
        try container.encodeIfPresent(date, forKey: .date)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(startTime, forKey: .startTime)
        try container.encodeIfPresent(durationMinutes, forKey: .durationMinutes)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(lat, forKey: .lat)
        try container.encodeIfPresent(lng, forKey: .lng)
        try container.encodeIfPresent(groups, forKey: .groups)
    }
}

extension ProjectSchedule {
    /// Some responses return the `schedule` column as a JSON string which may be double-encoded.
    /// This helper first attempts to decode the raw string and then retries by unwrapping any
    /// nested JSON string if needed.
    fileprivate static func decodeEmbeddedSchedules(from scheduleString: String) -> [ProjectScheduleItem]? {
        guard let directData = scheduleString.data(using: .utf8) else { return nil }

        let decoder = JSONDecoder()

        if let decoded = try? decoder.decode(EmbeddedScheduleResponse.self, from: directData) {
            return decoded.schedules
        }

        if let decodedDays = try? decoder.decode(EmbeddedDaysResponse.self, from: directData) {
            return decodedDays.days?.map { $0.asScheduleItem }
        }

        if let unwrappedString = try? decoder.decode(String.self, from: directData),
           let nestedData = unwrappedString.data(using: .utf8) {
            if let decoded = try? decoder.decode(EmbeddedScheduleResponse.self, from: nestedData) {
                return decoded.schedules
            }

            if let decodedDays = try? decoder.decode(EmbeddedDaysResponse.self, from: nestedData) {
                return decodedDays.days?.map { $0.asScheduleItem }
            }
        }

        return nil
    }
}

private struct EmbeddedScheduleResponse: Codable {
    let schedules: [ProjectScheduleItem]?
}

private struct EmbeddedDaysResponse: Codable {
    let days: [ScheduleDay]?
}

private struct ScheduleDay: Codable {
    let id: String?
    let title: String?
    let date: String?
    let startTime: String?
    @SafeOptionalInt var duration: Int?
    @SafeOptionalInt var durationMinutes: Int?
    let groups: [ScheduleGroup]?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case date
        case startTime = "start_time"
        case startTimeCamel = "startTime"
        case duration
        case durationMinutes
        case durationMinutesSnake = "duration_minutes"
        case groups
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        startTime = try container.decodeIfPresent(String.self, forKey: .startTime)
            ?? container.decodeIfPresent(String.self, forKey: .startTimeCamel)
        _duration = try container.decodeIfPresent(SafeOptionalInt.self, forKey: .duration) ?? SafeOptionalInt()
        _durationMinutes = try container.decodeIfPresent(SafeOptionalInt.self, forKey: .durationMinutes)
            ?? container.decodeIfPresent(SafeOptionalInt.self, forKey: .durationMinutesSnake) ?? SafeOptionalInt()
        groups = try container.decodeIfPresent([ScheduleGroup].self, forKey: .groups)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(date, forKey: .date)
        try container.encodeIfPresent(startTime, forKey: .startTime)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(durationMinutes, forKey: .durationMinutes)
        try container.encodeIfPresent(groups, forKey: .groups)
    }

    var asScheduleItem: ProjectScheduleItem {
        ProjectScheduleItem(
            id: id ?? date ?? title,
            title: title ?? "Schedule Day",
            date: date,
            lastUpdated: nil,
            startTime: startTime,
            duration: duration,
            durationMinutes: durationMinutes,
            groups: groups
        )
    }
}

struct ScheduleFetchResponse: Codable {
    @SafeBool var success: Bool
    let schedule: [ProjectSchedule]?
    let schedules: [ProjectSchedule]?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case schedule
        case schedules
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        _success = try container.decode(SafeBool.self, forKey: .success)
        error = try container.decodeIfPresent(String.self, forKey: .error)

        if let decodedArray = try container.decodeIfPresent([ProjectSchedule].self, forKey: .schedule) {
            schedule = decodedArray
        } else if let decodedSingle = try container.decodeIfPresent(ProjectSchedule.self, forKey: .schedule) {
            schedule = [decodedSingle]
        } else {
            schedule = nil
        }

        schedules = try container.decodeIfPresent([ProjectSchedule].self, forKey: .schedules)
    }
}

struct ProjectScheduleItem: Codable, Hashable {
    let id: String?
    let title: String
    let date: String?
    let lastUpdated: String?
    let startTime: String?
    @SafeOptionalInt var duration: Int?
    @SafeOptionalInt var durationMinutes: Int?
    let groups: [ScheduleGroup]?

    var listIdentifier: String { id ?? title }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case date
        case lastUpdated = "last_updated"
        case startTime = "start_time"
        case startTimeCamel = "startTime"
        case duration
        case durationMinutes
        case durationMinutesSnake = "duration_minutes"
        case groups
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        lastUpdated = try container.decodeIfPresent(String.self, forKey: .lastUpdated)
        startTime = try container.decodeIfPresent(String.self, forKey: .startTime)
            ?? container.decodeIfPresent(String.self, forKey: .startTimeCamel)
        duration = try container.decodeIfPresent(Int.self, forKey: .duration)
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes)
            ?? container.decodeIfPresent(Int.self, forKey: .durationMinutesSnake)
        groups = try container.decodeIfPresent([ScheduleGroup].self, forKey: .groups)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(date, forKey: .date)
        try container.encodeIfPresent(lastUpdated, forKey: .lastUpdated)
        try container.encodeIfPresent(startTime, forKey: .startTime)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(durationMinutes, forKey: .durationMinutes)
        try container.encodeIfPresent(groups, forKey: .groups)
    }

    init(
        id: String? = nil,
        title: String,
        date: String? = nil,
        lastUpdated: String? = nil,
        startTime: String? = nil,
        duration: Int? = nil,
        durationMinutes: Int? = nil,
        groups: [ScheduleGroup]? = nil
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.lastUpdated = lastUpdated
        self.startTime = startTime
        self.duration = duration
        self.durationMinutes = durationMinutes
        self.groups = groups
    }
}

struct ScheduleGroup: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let blocks: [ScheduleBlock]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case blocks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        blocks = try container.decodeIfPresent([ScheduleBlock].self, forKey: .blocks) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(blocks, forKey: .blocks)
    }
}

struct ScheduleBlock: Codable, Hashable, Identifiable {
    enum BlockType: String, Codable {
        case title
        case shot
        case unknown

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            self = BlockType(rawValue: rawValue) ?? .unknown
        }
    }

    let id: String
    let type: BlockType
    let duration: Int?
    let description: String?
    let color: String?
    let ignoreTime: Bool?
    let title: String?
    let calculatedStart: String?
    let lockedStartTime: String?
    let storyboards: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case duration
        case description
        case color
        case ignoreTime
        case title
        case calculatedStart
        case lockedStartTime
        case storyboards
    }
}

// MARK: - Tag Model

struct FrameTag: Codable, Identifiable {
    let id: String?
    let name: String
}

// MARK: - Frame Board

struct FrameBoard: Codable, Identifiable, Hashable {
    let id: String
    let label: String?
    let order: Int?
    @SafeBool var isPinned: Bool
    let fileUrl: String?
    let fileThumbUrl: String?
    let fileName: String?
    let fileType: String?
    @SafeOptionalInt var fileSize: Int?
    let fileCrop: String?
    let createdBy: String?
    let createdAt: String?
    let lastUpdated: String?

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case order
        case isPinned = "pinned"
        case fileUrl = "file_url"
        case fileThumbUrl = "file_thumb_url"
        case fileName = "file_name"
        case fileType = "file_type"
        case fileSize = "file_size"
        case fileCrop = "file_crop"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case lastUpdated = "last_updated"
    }
}

// MARK: - Frame Model

struct Frame: Codable, Identifiable {
    let id: String
    let creativeId: String
    let creativeTitle: String?
    let creativeColor: String?
    let creativeAspectRatio: String?
    let boards: [FrameBoard]?
    let mainBoardType: String?
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        creativeId = try container.decode(String.self, forKey: .creativeId)
        creativeTitle = try container.decodeIfPresent(String.self, forKey: .creativeTitle)
        creativeColor = try container.decodeIfPresent(String.self, forKey: .creativeColor)
        creativeAspectRatio = try container.decodeIfPresent(String.self, forKey: .creativeAspectRatio)
        boards = try container.decodeIfPresent([FrameBoard].self, forKey: .boards)
        mainBoardType = try container.decodeIfPresent(String.self, forKey: .mainBoardType)

        let primaryBoard = Frame.selectPrimaryBoard(from: boards, matching: mainBoardType)
        let photoBoard = Frame.selectPrimaryBoard(from: boards, matching: "photoboard")

        board = try container.decodeIfPresent(String.self, forKey: .board) ?? primaryBoard?.fileUrl
        boardThumb = try container.decodeIfPresent(String.self, forKey: .boardThumb) ?? primaryBoard?.fileThumbUrl
        boardFileName = try container.decodeIfPresent(String.self, forKey: .boardFileName) ?? primaryBoard?.fileName
        boardFileType = try container.decodeIfPresent(String.self, forKey: .boardFileType) ?? primaryBoard?.fileType
        _boardFileSize = try container.decodeIfPresent(SafeOptionalInt.self, forKey: .boardFileSize) ?? SafeOptionalInt(wrappedValue: primaryBoard?.fileSize)
        photoboard = try container.decodeIfPresent(String.self, forKey: .photoboard) ?? photoBoard?.fileUrl
        photoboardThumb = try container.decodeIfPresent(String.self, forKey: .photoboardThumb) ?? photoBoard?.fileThumbUrl
        photoboardFileName = try container.decodeIfPresent(String.self, forKey: .photoboardFileName) ?? photoBoard?.fileName
        photoboardFileType = try container.decodeIfPresent(String.self, forKey: .photoboardFileType) ?? photoBoard?.fileType
        _photoboardFileSize = try container.decodeIfPresent(SafeOptionalInt.self, forKey: .photoboardFileSize) ?? SafeOptionalInt(wrappedValue: photoBoard?.fileSize)
        photoboardCrop = try container.decodeIfPresent(String.self, forKey: .photoboardCrop) ?? photoBoard?.fileCrop
        preview = try container.decodeIfPresent(String.self, forKey: .preview)
        previewThumb = try container.decodeIfPresent(String.self, forKey: .previewThumb)
        previewFileName = try container.decodeIfPresent(String.self, forKey: .previewFileName)
        previewFileType = try container.decodeIfPresent(String.self, forKey: .previewFileType)
        _previewFileSize = try container.decodeIfPresent(SafeOptionalInt.self, forKey: .previewFileSize) ?? SafeOptionalInt()
        previewCrop = try container.decodeIfPresent(String.self, forKey: .previewCrop)
        captureClipId = try container.decodeIfPresent(String.self, forKey: .captureClipId)
        captureClip = try container.decodeIfPresent(String.self, forKey: .captureClip)
        captureClipThumbnail = try container.decodeIfPresent(String.self, forKey: .captureClipThumbnail)
        captureClipFileName = try container.decodeIfPresent(String.self, forKey: .captureClipFileName)
        captureClipFileType = try container.decodeIfPresent(String.self, forKey: .captureClipFileType)
        _captureClipFileSize = try container.decodeIfPresent(SafeOptionalInt.self, forKey: .captureClipFileSize) ?? SafeOptionalInt()
        captureClipCrop = try container.decodeIfPresent(String.self, forKey: .captureClipCrop)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        caption = try container.decodeIfPresent(String.self, forKey: .caption)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        crop = try container.decodeIfPresent(String.self, forKey: .crop)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        statusUpdated = try container.decodeIfPresent(String.self, forKey: .statusUpdated)
        _isArchived = try container.decodeIfPresent(SafeOptionalBool.self, forKey: .isArchived) ?? SafeOptionalBool()
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        lastUpdated = try container.decodeIfPresent(String.self, forKey: .lastUpdated)
        frameOrder = try container.decodeIfPresent(String.self, forKey: .frameOrder)
        frameShootOrder = try container.decodeIfPresent(String.self, forKey: .frameShootOrder)
        schedule = try container.decodeIfPresent(String.self, forKey: .schedule)
        frameStartTime = try container.decodeIfPresent(String.self, forKey: .frameStartTime)
        _frameHide = try container.decodeIfPresent(SafeOptionalBool.self, forKey: .frameHide) ?? SafeOptionalBool()
        _tags = try container.decodeIfPresent(SafeTags.self, forKey: .tags) ?? SafeTags(wrappedValue: [])
    }

    init(
        id: String,
        creativeId: String,
        creativeTitle: String? = nil,
        creativeColor: String? = nil,
        creativeAspectRatio: String? = nil,
        boards: [FrameBoard]? = nil,
        mainBoardType: String? = nil,
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
        self.boards = boards
        self.mainBoardType = mainBoardType
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
        case boards
        case mainBoardType = "main_board_type"
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

        let sortedBoards: [FrameBoard] = (boards ?? [])
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned {
                    return lhs.isPinned
                }
                return (lhs.order ?? Int.max) < (rhs.order ?? Int.max)
            }

        if !sortedBoards.isEmpty {
            for board in sortedBoards {
                items.append(
                    FrameAssetItem(
                        kind: .board,
                        primary: board.fileUrl,
                        fallback: board.fileThumbUrl,
                        fileType: board.fileType,
                        label: board.label
                    )
                )
            }
        } else if board != nil || boardThumb != nil {
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
            boards: boards,
            mainBoardType: mainBoardType,
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

    private static func selectPrimaryBoard(from boards: [FrameBoard]?, matching label: String?) -> FrameBoard? {
        guard let boards, !boards.isEmpty else { return nil }

        let filteredBoards: [FrameBoard]
        if let label, !label.isEmpty {
            filteredBoards = boards.filter { $0.label?.lowercased() == label.lowercased() }
        } else {
            filteredBoards = boards
        }

        if let pinned = filteredBoards.first(where: { $0.isPinned }) {
            return pinned
        }

        return filteredBoards.min { lhs, rhs in
            (lhs.order ?? Int.max) < (rhs.order ?? Int.max)
        }
    }
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
    let label: String?

    init(kind: FrameAssetKind, primary: String?, fallback: String?, fileType: String? = nil, label: String? = nil) {
        self.kind = kind
        self.primary = primary
        self.fallback = fallback
        self.fileType = fileType
        self.label = label
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

    var displayLabel: String { label ?? kind.displayName }
    var iconName: String { kind.systemImageName }

    private static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "webm", "mkv"]
}
