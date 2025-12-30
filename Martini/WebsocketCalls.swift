import Foundation

/// Centralizes handling of websocket-driven updates.
@MainActor
final class WebsocketCalls {
    private let authService: AuthService

    private let frameEvents: Set<String> = [
        "comment-added",
        "frame-status-updated",
        "frame-order-updated",
        "frame-image-updated",
        "frame-image-inserted",
        "frame-crop-updated",
        "frame-description-updated",
        "frame-board-updated",
        "frame-caption-updated",
        "update-clips",
        "reload"
    ]

    private let creativeEvents: Set<String> = [
        "creative-live-updated",
        "creative-deleted",
        "creative-title-updated",
        "creative-order-updated",
        "project-files-updated",
        "reload"
    ]

    private let scheduleEvents: Set<String> = [
        "activate-schedule",
        "update-schedule"
    ]

    init(authService: AuthService) {
        self.authService = authService
    }

    func handle(event name: String, dataString: String) {
        if name == "creative-aspect-ratio-updated" {
            Task { [weak self] in
                await self?.handleCreativeAspectRatioUpdate(dataString: dataString)
            }
            return
        }

        if frameEvents.contains(name) {
            Task { [weak self] in
                await self?.handleFrameEvent(name: name, dataString: dataString)
            }
        }

        if creativeEvents.contains(name) {
            Task { [weak self] in
                await self?.refreshCreatives()
            }
        }

        if scheduleEvents.contains(name) {
            Task { [weak self] in
                try? await self?.authService.fetchProjectDetails()
                try? await self?.authService.fetchFrames()
                self?.authService.publishScheduleUpdate(eventName: name)
            }
        }
    }

    private func handleFrameEvent(name: String, dataString: String) async {
        let frameId = frameIdentifier(from: dataString)

        switch name {
        case "frame-status-updated":
            if let frameStatusUpdate = FrameStatusUpdate.parse(dataString: dataString) {
                applyFrameStatusUpdate(frameStatusUpdate)
            } else {
                notifyFrameUpdate(id: frameId, eventName: name)
            }
            return

        case "frame-description-updated":
            if let frameDescriptionUpdate = FrameDescriptionUpdate.parse(dataString: dataString) {
                applyFrameDescriptionUpdate(frameDescriptionUpdate)
            } else {
                notifyFrameUpdate(id: frameId, eventName: name)
            }
            return

        case "frame-board-updated":
            if let frameBoardUpdate = FrameBoardUpdate.parse(dataString: dataString) {
                applyFrameBoardUpdate(frameBoardUpdate)
            } else {
                notifyFrameUpdate(id: frameId, eventName: name)
            }
            return

        case "frame-caption-updated":
            if let frameCaptionUpdate = FrameCaptionUpdate.parse(dataString: dataString) {
                applyFrameCaptionUpdate(frameCaptionUpdate)
            } else {
                notifyFrameUpdate(id: frameId, eventName: name)
            }
            return

        case "comment-added":
            notifyFrameUpdate(id: frameId, eventName: name)
            return

        default:
            break
        }

        try? await authService.fetchFrames()

        notifyFrameUpdate(id: frameId, eventName: name)
    }

    private func applyFrameStatusUpdate(_ update: FrameStatusUpdate) {
        let status = FrameStatus.fromAPIValue(update.status)

        if let index = authService.frames.firstIndex(where: { $0.id == update.id }) {
            authService.frames[index] = authService.frames[index].updatingStatus(status)
        }

        notifyFrameUpdate(id: update.id, eventName: "frame-status-updated")
    }

    private func applyFrameDescriptionUpdate(_ update: FrameDescriptionUpdate) {
        guard let frameId = update.resolvedId else { return }

        guard let index = authService.frames.firstIndex(where: { $0.id == frameId }) else { return }

        authService.frames[index] = authService.frames[index].updatingDescription(update.description)

        notifyFrameUpdate(id: frameId, eventName: "frame-description-updated")
    }

    private func applyFrameBoardUpdate(_ update: FrameBoardUpdate) {
        guard
            let frameId = update.resolvedId,
            let boards = update.boards,
            let index = authService.frames.firstIndex(where: { $0.id == frameId })
        else { return }

        authService.frames[index] = authService.frames[index].updatingBoards(boards, mainBoardType: update.mainBoardType)

        notifyFrameUpdate(id: frameId, eventName: "frame-board-updated")
    }

    private func applyFrameCaptionUpdate(_ update: FrameCaptionUpdate) {
        guard let frameId = update.resolvedId else { return }

        guard let index = authService.frames.firstIndex(where: { $0.id == frameId }) else { return }

        authService.frames[index] = authService.frames[index].updatingCaption(update.caption)

        notifyFrameUpdate(id: frameId, eventName: "frame-caption-updated")
    }

    private func refreshCreatives() async {
        try? await authService.fetchCreatives()
    }

    private func handleCreativeAspectRatioUpdate(dataString: String) async {
        guard let update = CreativeAspectRatioUpdate.parse(dataString: dataString) else { return }
        guard let creativeId = update.resolvedCreativeId,
              let aspectRatio = update.normalizedAspectRatio else { return }

        authService.updateFramesAspectRatio(creativeId: creativeId, aspectRatio: aspectRatio)
    }

    private func notifyFrameUpdate(id: String?, eventName: String) {
        guard let id else { return }
        authService.publishFrameUpdate(frameId: id, context: .websocket(event: eventName))
    }

    private func frameIdentifier(from dataString: String) -> String? {
        guard let data = dataString.data(using: .utf8) else { return nil }

        if let decoded = try? JSONDecoder().decode(FrameIdentifierPayload.self, from: data) {
            return decoded.resolvedId
        }

        if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
            if let id = json["id"] as? String {
                return id
            }

            if let frameId = json["frameId"] as? String {
                return frameId
            }

            if let camelFrameId = json["frameID"] as? String {
                return camelFrameId
            }

            if let snakeFrameId = json["frame_id"] as? String {
                return snakeFrameId
            }
        }

        return nil
    }
}

private struct FrameStatusUpdate: Codable {
    let id: String
    let status: String?

    static func parse(dataString: String) -> FrameStatusUpdate? {
        guard let data = dataString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(FrameStatusUpdate.self, from: data)
    }
}

private struct FrameDescriptionUpdate: Decodable {
    let id: String?
    let frameId: String?
    let frameID: String?
    let frame_id: String?
    let description: String?

    var resolvedId: String? { id ?? frameId ?? frameID ?? frame_id }

    static func parse(dataString: String) -> FrameDescriptionUpdate? {
        guard let data = dataString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(FrameDescriptionUpdate.self, from: data)
    }
}

private struct FrameBoardUpdate: Decodable {
    let id: String?
    let frameId: String?
    let frameID: String?
    let frame_id: String?
    let mainBoardType: String?
    let boards: [FrameBoard]?

    enum CodingKeys: String, CodingKey {
        case id
        case frameId
        case frameID
        case frame_id
        case mainBoardType = "main_board_type"
        case boards
    }

    var resolvedId: String? { id ?? frameId ?? frameID ?? frame_id }

    static func parse(dataString: String) -> FrameBoardUpdate? {
        guard let data = dataString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(FrameBoardUpdate.self, from: data)
    }
}

private struct FrameCaptionUpdate: Decodable {
    let id: String?
    let frameId: String?
    let frameID: String?
    let frame_id: String?
    let caption: String?

    var resolvedId: String? { id ?? frameId ?? frameID ?? frame_id }

    static func parse(dataString: String) -> FrameCaptionUpdate? {
        guard let data = dataString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(FrameCaptionUpdate.self, from: data)
    }
}

private struct FrameIdentifierPayload: Decodable {
    let id: String?
    let frameId: String?
    let frameID: String?
    let frame_id: String?

    var resolvedId: String? {
        id ?? frameId ?? frameID ?? frame_id
    }
}

private struct CreativeAspectRatioUpdate: Decodable {
    let creativeId: String?
    let creativeID: String?
    let creative_id: String?
    let aspectRatio: String?
    let aspect_ratio: String?

    var resolvedCreativeId: String? {
        creativeId ?? creativeID ?? creative_id
    }

    var normalizedAspectRatio: String? {
        guard let aspectRatio else { return nil }
        let trimmed = aspectRatio.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "1" {
            return "1 / 1"
        }
        return trimmed
    }

    static func parse(dataString: String) -> CreativeAspectRatioUpdate? {
        guard let data = dataString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CreativeAspectRatioUpdate.self, from: data)
    }
}
