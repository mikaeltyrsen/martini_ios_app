import SwiftUI

struct FullscreenMediaConfiguration: Identifiable {
    let id = UUID()
    let media: MediaItem
    let config: MediaViewerConfig
    let metadataItem: BoardMetadataItem?
    let thumbnailURL: URL?
}

final class FullscreenMediaCoordinator: ObservableObject {
    @Published var configuration: FullscreenMediaConfiguration?
}

private struct FullscreenMediaCoordinatorKey: EnvironmentKey {
    static let defaultValue: FullscreenMediaCoordinator? = nil
}

extension EnvironmentValues {
    var fullscreenMediaCoordinator: FullscreenMediaCoordinator? {
        get { self[FullscreenMediaCoordinatorKey.self] }
        set { self[FullscreenMediaCoordinatorKey.self] = newValue }
    }
}

extension View {
    func fullscreenMediaCoordinator(_ coordinator: FullscreenMediaCoordinator?) -> some View {
        environment(\.fullscreenMediaCoordinator, coordinator)
    }
}
