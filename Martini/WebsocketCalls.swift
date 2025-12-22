import Foundation

/// Centralizes handling of websocket-driven updates.
@MainActor
final class WebsocketCalls {
    private let authService: AuthService

    private let frameEvents: Set<String> = [
        "frame-status-updated",
        "frame-order-updated",
        "frame-image-updated",
        "frame-image-inserted",
        "frame-crop-updated",
        "frame-description-updated",
        "frame-caption-updated",
        "update-clips",
        "reload"
    ]

    private let creativeEvents: Set<String> = [
        "creative-live-updated",
        "creative-deleted",
        "creative-title-updated",
        "creative-order-updated",
        "creative-aspect-ratio-updated",
        "activate-schedule",
        "update-schedule",
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
            }
        }
    }

    private func handleFrameEvent(name: String, dataString: String) async {
        if name == "frame-status-updated", let frameStatusUpdate = FrameStatusUpdate.parse(dataString: dataString) {
            applyFrameStatusUpdate(frameStatusUpdate)
            return
        }

        try? await authService.fetchFrames()

        if name == "frame-status-updated" {
            await refreshCreatives()
        }
    }

    private func applyFrameStatusUpdate(_ update: FrameStatusUpdate) {
        guard let status = FrameStatus(rawValue: update.status) else { return }

        if let index = authService.frames.firstIndex(where: { $0.id == update.id }) {
            authService.frames[index] = authService.frames[index].updatingStatus(status)
        }

        Task { [weak self] in
            await self?.refreshCreatives()
        }
    }

    private func refreshCreatives() async {
        try? await authService.fetchCreatives()
    }
}

private struct FrameStatusUpdate: Codable {
    let id: String
    let status: String

    static func parse(dataString: String) -> FrameStatusUpdate? {
        guard let data = dataString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(FrameStatusUpdate.self, from: data)
    }
}
