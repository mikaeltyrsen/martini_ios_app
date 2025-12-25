import Foundation

final class ProjectKitSelectionStore {
    static let shared = ProjectKitSelectionStore()

    private let defaults = UserDefaults.standard

    private init() {}

    func cameraIds(for projectId: String) -> [String] {
        defaults.stringArray(forKey: cameraKey(projectId: projectId)) ?? []
    }

    func lensIds(for projectId: String) -> [String] {
        defaults.stringArray(forKey: lensKey(projectId: projectId)) ?? []
    }

    func saveCameraIds(_ ids: [String], for projectId: String) {
        defaults.set(Array(Set(ids)).sorted(), forKey: cameraKey(projectId: projectId))
    }

    func saveLensIds(_ ids: [String], for projectId: String) {
        defaults.set(Array(Set(ids)).sorted(), forKey: lensKey(projectId: projectId))
    }

    private func cameraKey(projectId: String) -> String {
        "project_kit_cameras_\(projectId)"
    }

    private func lensKey(projectId: String) -> String {
        "project_kit_lenses_\(projectId)"
    }
}
