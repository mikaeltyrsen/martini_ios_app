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
struct SafeString: Codable, Equatable, Hashable {
    var wrappedValue: String

    init(wrappedValue: String = "") {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let stringValue = try? container.decode(String.self) {
            wrappedValue = stringValue
            return
        }

        if let intValue = try? container.decode(Int.self) {
            wrappedValue = String(intValue)
            return
        }

        if let doubleValue = try? container.decode(Double.self) {
            wrappedValue = String(doubleValue)
            return
        }

        if let boolValue = try? container.decode(Bool.self) {
            wrappedValue = String(boolValue)
            return
        }

        wrappedValue = ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

@propertyWrapper
struct SafeOptionalString: Codable, Equatable, Hashable {
    var wrappedValue: String?

    init(wrappedValue: String? = nil) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            wrappedValue = nil
            return
        }

        if let stringValue = try? container.decode(String.self) {
            wrappedValue = stringValue
            return
        }

        if let intValue = try? container.decode(Int.self) {
            wrappedValue = String(intValue)
            return
        }

        if let doubleValue = try? container.decode(Double.self) {
            wrappedValue = String(doubleValue)
            return
        }

        if let boolValue = try? container.decode(Bool.self) {
            wrappedValue = String(boolValue)
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
    let projectId: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case creatives
        case projectId
        case projectID = "project_id"
        case error
    }

    init(success: Bool, creatives: [Creative], projectId: String? = nil, error: String? = nil) {
        _success = SafeBool(wrappedValue: success)
        self.creatives = creatives
        self.projectId = projectId
        self.error = error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        _success = try container.decode(SafeBool.self, forKey: .success)
        creatives = try container.decode([Creative].self, forKey: .creatives)
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId)
            ?? container.decodeIfPresent(String.self, forKey: .projectID)
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(_success, forKey: .success)
        try container.encode(creatives, forKey: .creatives)
        try container.encodeIfPresent(projectId, forKey: .projectID)
        try container.encodeIfPresent(error, forKey: .error)
    }
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
        } else if let scheduleObject = try container.decodeIfPresent(EmbeddedScheduleContainer.self, forKey: .schedule) {
            schedules = scheduleObject.asScheduleItems
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
        guard var data = scheduleString.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()

        func decodeSchedules(from data: Data) -> [ProjectScheduleItem]? {
            if let decoded = try? decoder.decode(EmbeddedScheduleResponse.self, from: data) {
                return decoded.schedules
            }

            if let decodedDays = try? decoder.decode(EmbeddedDaysResponse.self, from: data) {
                return decodedDays.days?.map { $0.asScheduleItem }
            }

            if let decodedContainer = try? decoder.decode(EmbeddedDaysContainerResponse.self, from: data) {
                if let wrappedDays = decodedContainer.schedule?.days ?? decodedContainer.days {
                    return wrappedDays.map { $0.asScheduleItem }
                }
            }

            return nil
        }

        // Attempt to decode up to two layers of nested string encoding.
        for _ in 0..<2 {
            if let schedules = decodeSchedules(from: data) {
                return schedules
            }

            if let unwrappedString = try? decoder.decode(String.self, from: data),
               let nestedData = unwrappedString.data(using: .utf8) {
                data = nestedData
                continue
            }

            break
        }

        return decodeSchedules(from: data)
    }
}

private struct EmbeddedScheduleResponse: Codable {
    let schedules: [ProjectScheduleItem]?
}

private struct EmbeddedDaysResponse: Codable {
    let days: [ScheduleDay]?
}

private struct EmbeddedDaysContainerResponse: Codable {
    let schedule: EmbeddedDaysResponse?
    let days: [ScheduleDay]?
}

private final class EmbeddedScheduleContainer: Codable {
    let schedules: [ProjectScheduleItem]?
    let days: [ScheduleDay]?
    let schedule: EmbeddedScheduleContainer?

    var asScheduleItems: [ProjectScheduleItem]? {
        if let schedules, !schedules.isEmpty {
            return schedules
        }

        if let days, !days.isEmpty {
            return days.map { $0.asScheduleItem }
        }

        if let nested = schedule {
            return nested.asScheduleItems
        }

        return nil
    }
}

private struct ScheduleDay: Codable {
    let id: String?
    let title: String?
    let date: String?
    let startTime: String?
    @SafeOptionalInt var duration: Int?
    @SafeOptionalInt var durationMinutes: Int?
    let location: String?
    let lat: Double?
    let lng: Double?
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
        case location
        case lat
        case lng
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
        location = try container.decodeIfPresent(String.self, forKey: .location)
        lat = try container.decodeIfPresent(Double.self, forKey: .lat)
        lng = try container.decodeIfPresent(Double.self, forKey: .lng)
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
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(lat, forKey: .lat)
        try container.encodeIfPresent(lng, forKey: .lng)
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
            location: location,
            lat: lat,
            lng: lng,
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
    let location: String?
    let lat: Double?
    let lng: Double?
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
        case location
        case lat
        case lng
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
        location = try container.decodeIfPresent(String.self, forKey: .location)
        lat = try container.decodeIfPresent(Double.self, forKey: .lat)
        lng = try container.decodeIfPresent(Double.self, forKey: .lng)
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
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(lat, forKey: .lat)
        try container.encodeIfPresent(lng, forKey: .lng)
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
        location: String? = nil,
        lat: Double? = nil,
        lng: Double? = nil,
        groups: [ScheduleGroup]? = nil
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.lastUpdated = lastUpdated
        self.startTime = startTime
        self.duration = duration
        self.durationMinutes = durationMinutes
        self.location = location
        self.lat = lat
        self.lng = lng
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

    init(
        id: String = UUID().uuidString,
        type: BlockType,
        duration: Int? = nil,
        description: String? = nil,
        color: String? = nil,
        ignoreTime: Bool? = nil,
        title: String? = nil,
        calculatedStart: String? = nil,
        lockedStartTime: String? = nil,
        storyboards: [String]? = nil
    ) {
        self.id = id
        self.type = type
        self.duration = duration
        self.description = description
        self.color = color
        self.ignoreTime = ignoreTime
        self.title = title
        self.calculatedStart = calculatedStart
        self.lockedStartTime = lockedStartTime
        self.storyboards = storyboards
    }

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

extension ScheduleGroup {
    init(id: String, title: String, blocks: [ScheduleBlock]) {
        self.id = id
        self.title = title
        self.blocks = blocks
    }
}

// MARK: - Tag Model

struct FrameTag: Codable, Identifiable, Hashable {
    let id: String?
    let name: String
    let groupName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case groupName = "group"
        case tagTypeName = "tag_type_name"
        case tagGroup = "tag_group"
        case typeName = "type_name"
    }

    init(id: String?, name: String, groupName: String? = nil) {
        self.id = id
        self.name = name
        self.groupName = groupName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        let decodedGroup = try container.decodeIfPresent(String.self, forKey: .groupName)
        let decodedType = try container.decodeIfPresent(String.self, forKey: .tagTypeName)
        let decodedTagGroup = try container.decodeIfPresent(String.self, forKey: .tagGroup)
        let decodedTypeName = try container.decodeIfPresent(String.self, forKey: .typeName)

        groupName = decodedGroup ?? decodedType ?? decodedTagGroup ?? decodedTypeName
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(groupName, forKey: .groupName)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id ?? name.lowercased())
    }

    static func == (lhs: FrameTag, rhs: FrameTag) -> Bool {
        lhs.id ?? lhs.name.lowercased() == rhs.id ?? rhs.name.lowercased()
    }
}

// MARK: - Tag Group Model

struct TagGroupDefinition: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let color: String?
    let icon: String?
    let order: Int?
    let tags: [FrameTag]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case color
        case icon
        case order
        case tags
    }
}

enum JSONValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
            return
        }
        if let intValue = try? container.decode(Int.self) {
            self = .number(Double(intValue))
            return
        }
        if let doubleValue = try? container.decode(Double.self) {
            self = .number(doubleValue)
            return
        }
        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
            return
        }
        if let arrayValue = try? container.decode([JSONValue].self) {
            self = .array(arrayValue)
            return
        }
        if let objectValue = try? container.decode([String: JSONValue].self) {
            self = .object(objectValue)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var anyValue: Any {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value
        case .bool(let value):
            return value
        case .object(let value):
            return value.mapValues { $0.anyValue }
        case .array(let value):
            return value.map { $0.anyValue }
        case .null:
            return NSNull()
        }
    }
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
    let metadata: JSONValue?
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
        case metadata
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

        board = try container.decodeIfPresent(String.self, forKey: .board) ?? primaryBoard?.fileUrl
        boardThumb = try container.decodeIfPresent(String.self, forKey: .boardThumb) ?? primaryBoard?.fileThumbUrl
        boardFileName = try container.decodeIfPresent(String.self, forKey: .boardFileName) ?? primaryBoard?.fileName
        boardFileType = try container.decodeIfPresent(String.self, forKey: .boardFileType) ?? primaryBoard?.fileType
        _boardFileSize = try container.decodeIfPresent(SafeOptionalInt.self, forKey: .boardFileSize) ?? SafeOptionalInt(wrappedValue: primaryBoard?.fileSize)
        photoboard = try container.decodeIfPresent(String.self, forKey: .photoboard)
        photoboardThumb = try container.decodeIfPresent(String.self, forKey: .photoboardThumb)
        photoboardFileName = try container.decodeIfPresent(String.self, forKey: .photoboardFileName)
        photoboardFileType = try container.decodeIfPresent(String.self, forKey: .photoboardFileType)
        _photoboardFileSize = try container.decodeIfPresent(SafeOptionalInt.self, forKey: .photoboardFileSize) ?? SafeOptionalInt()
        photoboardCrop = try container.decodeIfPresent(String.self, forKey: .photoboardCrop)
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
        FrameStatus.fromAPIValue(status)
    }

    /// Returns the available assets for this frame in the order they should be shown by default.
    var availableAssets: [FrameAssetItem] {
        var items: [FrameAssetItem] = []

        let boardsList: [FrameBoard] = boards ?? []
        let sortedBoards: [FrameBoard] = boardsList.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned
            }
            return (lhs.order ?? Int.max) < (rhs.order ?? Int.max)
        }

        if !sortedBoards.isEmpty {
            for board in sortedBoards {
                items.append(
                    FrameAssetItem(
                        id: board.id,
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
                    id: "board-main",
                    kind: .board,
                    primary: board,
                    fallback: boardThumb,
                    fileType: boardFileType
                )
            )
        }

        let hasMatchingPhotoboard = boardsList.contains { board in
            (photoboard != nil && board.fileUrl == photoboard) ||
            (photoboardThumb != nil && board.fileThumbUrl == photoboardThumb)
        }

        if (photoboard != nil || photoboardThumb != nil), !hasMatchingPhotoboard {
            items.append(
                FrameAssetItem(
                    id: "photoboard",
                    kind: .board,
                    primary: photoboard,
                    fallback: photoboardThumb,
                    fileType: photoboardFileType
                )
            )
        }

        if preview != nil || previewThumb != nil {
            items.append(
                FrameAssetItem(
                    id: "preview",
                    kind: .preview,
                    primary: preview,
                    fallback: previewThumb,
                    fileType: previewFileType
                )
            )
        } else if captureClipThumbnail != nil || captureClip != nil {
            items.append(
                FrameAssetItem(
                    id: "captureClip",
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
        copyFrame(status: .some(status == .none ? nil : status.rawValue))
    }

    func updatingDescription(_ description: String?) -> Frame {
        copyFrame(description: description)
    }

    func updatingCaption(_ caption: String?) -> Frame {
        copyFrame(caption: caption)
    }

    func updatingCreativeAspectRatio(_ aspectRatio: String?) -> Frame {
        copyFrame(creativeAspectRatio: aspectRatio)
    }

    func updatingBoards(_ boards: [FrameBoard], mainBoardType: String?) -> Frame {
        let primaryBoard = Frame.selectPrimaryBoard(from: boards, matching: mainBoardType)

        return copyFrame(
            boards: boards,
            mainBoardType: mainBoardType,
            board: primaryBoard?.fileUrl,
            boardThumb: primaryBoard?.fileThumbUrl,
            boardFileName: primaryBoard?.fileName,
            boardFileType: primaryBoard?.fileType,
            boardFileSize: primaryBoard?.fileSize
        )
    }

    private func copyFrame(
        description: String? = nil,
        caption: String? = nil,
        status: String?? = nil,
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
        photoboardCrop: String? = nil
    ) -> Frame {
        Frame(
            id: id,
            creativeId: creativeId,
            creativeTitle: creativeTitle,
            creativeColor: creativeColor,
            creativeAspectRatio: creativeAspectRatio ?? self.creativeAspectRatio,
            boards: boards ?? self.boards,
            mainBoardType: mainBoardType ?? self.mainBoardType,
            board: board ?? self.board,
            boardThumb: boardThumb ?? self.boardThumb,
            boardFileName: boardFileName ?? self.boardFileName,
            boardFileType: boardFileType ?? self.boardFileType,
            boardFileSize: boardFileSize ?? self.boardFileSize,
            photoboard: photoboard ?? self.photoboard,
            photoboardThumb: photoboardThumb ?? self.photoboardThumb,
            photoboardFileName: photoboardFileName ?? self.photoboardFileName,
            photoboardFileType: photoboardFileType ?? self.photoboardFileType,
            photoboardFileSize: photoboardFileSize ?? self.photoboardFileSize,
            photoboardCrop: photoboardCrop ?? self.photoboardCrop,
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
            description: description ?? self.description,
            caption: caption ?? self.caption,
            notes: notes,
            crop: crop,
            status: status ?? self.status,
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
    let tagGroups: [TagGroupDefinition]?

    enum CodingKeys: String, CodingKey {
        case success
        case frames
        case error
        case tagGroups
        case tag_groups
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _success = try container.decodeIfPresent(SafeBool.self, forKey: .success) ?? SafeBool()
        frames = try container.decodeIfPresent([Frame].self, forKey: .frames) ?? []
        error = try container.decodeIfPresent(String.self, forKey: .error)
        let decodedTagGroups = try container.decodeIfPresent([TagGroupDefinition].self, forKey: .tagGroups)
        if let decodedTagGroups {
            tagGroups = decodedTagGroups
        } else {
            tagGroups = try container.decodeIfPresent([TagGroupDefinition].self, forKey: .tag_groups)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(success, forKey: .success)
        try container.encode(frames, forKey: .frames)
        try container.encodeIfPresent(error, forKey: .error)
        try container.encodeIfPresent(tagGroups, forKey: .tagGroups)
    }
}

struct UpdateFrameStatusResponse: Codable {
    @SafeBool var success: Bool
    let frame: Frame?
    let error: String?
}

struct UpdateBoardResponse: Codable {
    @SafeBool var success: Bool
    let error: String?
    let id: String?
    let frameId: String?
    let frameID: String?
    let frame_id: String?
    let mainBoardType: String?
    let boards: [FrameBoard]?

    enum CodingKeys: String, CodingKey {
        case success
        case error
        case id
        case frameId
        case frameID
        case frame_id
        case mainBoardType = "main_board_type"
        case boards
    }

    var resolvedId: String? { id ?? frameId ?? frameID ?? frame_id }
}

struct BasicResponse: Codable {
    @SafeBool var success: Bool
    let error: String?
}

// MARK: - Clips

struct Clip: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let fileName: String?
    let fileNameRaw: String?
    let fileType: String?
    @SafeOptionalInt var fileSize: Int?
    let thumbnail: String?
    let previewURL: String?
    let linkType: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case fileName = "file_name"
        case fileNameRaw = "file_name_raw"
        case fileType = "file_type"
        case fileSize = "file_size"
        case thumbnail
        case previewURL = "preview_url"
        case linkType = "link_type"
    }

    var fileURL: URL? {
        if let fileName, let url = URL(string: fileName) { return url }
        return nil
    }

    var thumbnailURL: URL? {
        if let thumbnail, let url = URL(string: thumbnail) { return url }
        return nil
    }

    var displayName: String {
        name?.isEmpty == false ? name! : (fileNameRaw ?? fileURL?.lastPathComponent ?? "Clip")
    }

    var isVideo: Bool {
        guard let lowercased = fileType?.lowercased() ?? fileURL?.pathExtension.lowercased() else { return false }
        return Clip.videoExtensions.contains(lowercased) || (fileType?.lowercased().contains("video") ?? false)
    }

    var isImage: Bool {
        guard let lowercased = fileType?.lowercased() ?? fileURL?.pathExtension.lowercased() else { return false }
        return Clip.imageExtensions.contains(lowercased) || (fileType?.lowercased().contains("image") ?? false)
    }

    var systemIconName: String {
        if isVideo { return "video" }
        if isImage { return "photo" }
        if isPDF { return "doc.richtext" }
        if isAudio { return "waveform" }
        return "doc"
    }

    private var isPDF: Bool {
        fileType?.lowercased().contains("pdf") == true || fileURL?.pathExtension.lowercased() == "pdf"
    }

    private var isAudio: Bool {
        guard let lowercased = fileType?.lowercased() ?? fileURL?.pathExtension.lowercased() else { return false }
        return ["mp3", "wav", "aac", "m4a"].contains(lowercased) || (fileType?.lowercased().contains("audio") ?? false)
    }

    var formattedFileSize: String? {
        guard let fileSize else { return nil }
        return Clip.byteFormatter.string(fromByteCount: Int64(fileSize))
    }

    private static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "webm", "mkv", "m3u8"]
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "heic", "webp"]
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()
}

struct ClipsResponse: Codable {
    @SafeBool var success: Bool
    let clips: [Clip]
    let error: String?
}

// MARK: - Comments

struct Comment: Codable, Identifiable, Hashable {
    @SafeString var id: String
    @SafeOptionalString var userId: String?
    let guestName: String?
    let comment: String?
    @SafeOptionalString var marker: String?
    @SafeOptionalString var status: String?
    let frameId: String?
    @SafeOptionalInt var frameOrder: Int?
    let lastUpdated: String?
    let name: String?
    let replies: [Comment]
    let frameThumb: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case guestName = "guest_name"
        case comment
        case marker
        case status
        case frameId = "frame_id"
        case frameOrder = "frame_order"
        case lastUpdated = "last_updated"
        case name
        case replies
        case frameThumb = "frame_thumb"
    }

    init(
        id: String,
        userId: String? = nil,
        guestName: String? = nil,
        comment: String? = nil,
        marker: String? = nil,
        status: String? = nil,
        frameId: String? = nil,
        frameOrder: Int? = nil,
        lastUpdated: String? = nil,
        name: String? = nil,
        replies: [Comment] = [],
        frameThumb: String? = nil
    ) {
        _id = SafeString(wrappedValue: id)
        _userId = SafeOptionalString(wrappedValue: userId)
        self.guestName = guestName
        self.comment = comment
        _marker = SafeOptionalString(wrappedValue: marker)
        _status = SafeOptionalString(wrappedValue: status)
        self.frameId = frameId
        _frameOrder = SafeOptionalInt(wrappedValue: frameOrder)
        self.lastUpdated = lastUpdated
        self.name = name
        self.replies = replies
        self.frameThumb = frameThumb
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _id = try container.decode(SafeString.self, forKey: .id)
        _userId = try container.decodeIfPresent(SafeOptionalString.self, forKey: .userId) ?? SafeOptionalString()
        guestName = try container.decodeIfPresent(String.self, forKey: .guestName)
        comment = try container.decodeIfPresent(String.self, forKey: .comment)
        _marker = try container.decodeIfPresent(SafeOptionalString.self, forKey: .marker) ?? SafeOptionalString()
        _status = try container.decodeIfPresent(SafeOptionalString.self, forKey: .status) ?? SafeOptionalString()
        frameId = try container.decodeIfPresent(String.self, forKey: .frameId)
        _frameOrder = try container.decodeIfPresent(SafeOptionalInt.self, forKey: .frameOrder) ?? SafeOptionalInt()
        lastUpdated = try container.decodeIfPresent(String.self, forKey: .lastUpdated)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        replies = try container.decodeIfPresent([Comment].self, forKey: .replies) ?? []
        frameThumb = try container.decodeIfPresent(String.self, forKey: .frameThumb)
    }
}

struct CommentsResponse: Codable {
    @SafeBool var success: Bool
    let comments: [Comment]
    let currentUserId: String?
    @SafeBool var isProjectAdmin: Bool
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case comments
        case currentUserId = "currentUserId"
        case isProjectAdmin
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _success = try container.decodeIfPresent(SafeBool.self, forKey: .success) ?? SafeBool(wrappedValue: true)
        comments = try container.decodeIfPresent([Comment].self, forKey: .comments) ?? []
        if let stringValue = try container.decodeIfPresent(String.self, forKey: .currentUserId) {
            currentUserId = stringValue
        } else if let intValue = try container.decodeIfPresent(Int.self, forKey: .currentUserId) {
            currentUserId = String(intValue)
        } else {
            currentUserId = nil
        }
        _isProjectAdmin = try container.decodeIfPresent(SafeBool.self, forKey: .isProjectAdmin) ?? SafeBool()
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }
}

// MARK: - Frame Assets

enum FrameAssetKind: String, CaseIterable, Hashable {
    case board
    case preview

    var displayName: String {
        switch self {
        case .board:
            return "Empty Board"
        case .preview:
            return "Preview"
        }
    }

    var systemImageName: String {
        switch self {
        case .board:
            return "square.on.square"
        case .preview:
            return "video"
        }
    }
}

struct FrameAssetItem: Identifiable, Hashable {
    let id: String
    let kind: FrameAssetKind
    private let primary: String?
    private let fallback: String?
    private let fileType: String?
    let label: String?

    init(
        id: String = UUID().uuidString,
        kind: FrameAssetKind,
        primary: String?,
        fallback: String?,
        fileType: String? = nil,
        label: String? = nil
    ) {
        self.id = id
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

    var thumbnailURL: URL? {
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
