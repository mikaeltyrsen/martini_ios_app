import Foundation
import Combine

@MainActor
final class ProjectKitStore: ObservableObject {
    @Published private(set) var availableCameras: [DBCamera] = []
    @Published private(set) var availableLenses: [DBLens] = []
    @Published var selectedCameraIds: Set<String> = []
    @Published var selectedLensIds: Set<String> = []

    private let database = LocalDatabase.shared

    func load(for projectId: String?) {
        PackImporter.importPackIfNeeded(using: database)
        availableCameras = Self.deduplicate(
            database.fetchCameras()
                .filter { !$0.brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .filter { !$0.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        )
        availableLenses = Self.deduplicate(
            database.fetchLenses()
                .filter { !$0.brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .filter { !$0.series.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        )

        guard let projectId else { return }
        selectedCameraIds = Set(database.fetchProjectCameraIds(projectId: projectId))
        selectedLensIds = Set(database.fetchProjectLensIds(projectId: projectId))
    }

    func toggleCamera(_ camera: DBCamera, projectId: String?) {
        if selectedCameraIds.contains(camera.id) {
            selectedCameraIds.remove(camera.id)
        } else {
            selectedCameraIds.insert(camera.id)
        }
        persist(projectId: projectId)
    }

    func addCameras(ids: [String], projectId: String?) {
        selectedCameraIds = selectedCameraIds.union(ids)
        persist(projectId: projectId)
    }

    func addLenses(ids: [String], projectId: String?) {
        selectedLensIds = selectedLensIds.union(ids)
        persist(projectId: projectId)
    }

    func removeCamera(id: String, projectId: String?) {
        var updated = selectedCameraIds
        updated.remove(id)
        selectedCameraIds = updated
        persist(projectId: projectId)
    }

    func removeLens(id: String, projectId: String?) {
        var updated = selectedLensIds
        updated.remove(id)
        selectedLensIds = updated
        persist(projectId: projectId)
    }

    func toggleLens(_ lens: DBLens, projectId: String?) {
        if selectedLensIds.contains(lens.id) {
            selectedLensIds.remove(lens.id)
        } else {
            selectedLensIds.insert(lens.id)
        }
        persist(projectId: projectId)
    }

    func persist(projectId: String?) {
        guard let projectId else { return }
        database.updateProjectCameras(projectId: projectId, cameraIds: Array(selectedCameraIds))
        database.updateProjectLenses(projectId: projectId, lensIds: Array(selectedLensIds))
    }

    func selectedCameras() -> [DBCamera] {
        availableCameras.filter { selectedCameraIds.contains($0.id) }
            .sorted { "\($0.brand) \($0.model)" < "\($1.brand) \($1.model)" }
    }

    func selectedLenses() -> [DBLens] {
        availableLenses.filter { selectedLensIds.contains($0.id) }
            .sorted { "\($0.brand) \($0.series)" < "\($1.brand) \($1.series)" }
    }

    private static func deduplicate<T: Identifiable>(_ items: [T]) -> [T] where T.ID: Hashable {
        var seen: Set<T.ID> = []
        return items.filter { item in
            if seen.contains(item.id) { return false }
            seen.insert(item.id)
            return true
        }
    }
}
