import SwiftUI

struct FullscreenMediaConfiguration: Identifiable {
    let id = UUID()
    let url: URL?
    let isVideo: Bool
    let aspectRatio: CGFloat
    let title: String?
    let frameNumberLabel: String?
    let namespace: Namespace.ID
    let heroID: String
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
