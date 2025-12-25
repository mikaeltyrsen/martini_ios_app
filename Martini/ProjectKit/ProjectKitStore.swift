import Foundation
import Combine

@MainActor
final class ProjectKitStore: ObservableObject {
    struct LensPackGroup: Identifiable, Hashable {
        let id: String
        let pack: PackLensPack
        let lenses: [DBLens]

        var displayName: String {
            "\(pack.brand) \(pack.name)"
        }
    }

    @Published private(set) var availableCameras: [DBCamera] = []
    @Published private(set) var availableLenses: [DBLens] = []
    @Published var selectedCameraIds: Set<String> = []
    @Published var selectedLensIds: Set<String> = []

    private let dataStore = LocalJSONStore.shared
    private let selectionStore = ProjectKitSelectionStore.shared
    private var currentProjectId: String?

    func load(for projectId: String?) {
        currentProjectId = projectId
        loadAvailableKit()

        guard let projectId else {
            selectedCameraIds = []
            selectedLensIds = []
            return
        }
        selectedCameraIds = Set(selectionStore.cameraIds(for: projectId))
        selectedLensIds = Set(selectionStore.lensIds(for: projectId))
    }

    func toggleCamera(_ camera: DBCamera, projectId: String?) {
        if selectedCameraIds.contains(camera.id) {
            selectedCameraIds.remove(camera.id)
        } else {
            selectedCameraIds.insert(camera.id)
        }
        persist(projectId: projectId ?? currentProjectId)
    }

    func addCameras(ids: [String], projectId: String?) {
        selectedCameraIds = selectedCameraIds.union(ids)
        persist(projectId: projectId ?? currentProjectId)
    }

    func addLenses(ids: [String], projectId: String?) {
        selectedLensIds = selectedLensIds.union(ids)
        persist(projectId: projectId ?? currentProjectId)
    }

    func removeCamera(id: String, projectId: String?) {
        var updated = selectedCameraIds
        updated.remove(id)
        selectedCameraIds = updated
        persist(projectId: projectId ?? currentProjectId)
    }

    func removeLens(id: String, projectId: String?) {
        var updated = selectedLensIds
        updated.remove(id)
        selectedLensIds = updated
        persist(projectId: projectId ?? currentProjectId)
    }

    func toggleLens(_ lens: DBLens, projectId: String?) {
        if selectedLensIds.contains(lens.id) {
            selectedLensIds.remove(lens.id)
        } else {
            selectedLensIds.insert(lens.id)
        }
        persist(projectId: projectId ?? currentProjectId)
    }

    func persist(projectId: String?) {
        guard let projectId else { return }
        selectionStore.saveCameraIds(Array(selectedCameraIds), for: projectId)
        selectionStore.saveLensIds(Array(selectedLensIds), for: projectId)
        reloadSelections(projectId: projectId)
    }

    func selectedCameras() -> [DBCamera] {
        availableCameras.filter { selectedCameraIds.contains($0.id) }
            .sorted { "\($0.brand) \($0.model)" < "\($1.brand) \($1.model)" }
    }

    func selectedLenses() -> [DBLens] {
        availableLenses.filter { selectedLensIds.contains($0.id) }
            .sorted { "\($0.brand) \($0.series)" < "\($1.brand) \($1.series)" }
    }

    func availableLensPacks() -> [LensPackGroup] {
        let lensLookup = Dictionary(uniqueKeysWithValues: availableLenses.map { ($0.id, $0) })
        let itemsByPack = Dictionary(grouping: dataStore.lensPackItems, by: \.packId)
        let packs = dataStore.lensPacks.compactMap { pack -> LensPackGroup? in
            let sortedItems = (itemsByPack[pack.id] ?? []).sorted { $0.sortOrder < $1.sortOrder }
            let lenses = sortedItems.compactMap { lensLookup[$0.lensId] }
                .filter { !selectedLensIds.contains($0.id) }
            guard !lenses.isEmpty else { return nil }
            return LensPackGroup(id: pack.id, pack: pack, lenses: lenses)
        }
        return packs.sorted { $0.displayName < $1.displayName }
    }

    private static func deduplicate<T: Identifiable>(_ items: [T]) -> [T] where T.ID: Hashable {
        var seen: Set<T.ID> = []
        return items.filter { item in
            if seen.contains(item.id) { return false }
            seen.insert(item.id)
            return true
        }
    }

    private func loadAvailableKit() {
        availableCameras = Self.deduplicate(dataStore.fetchCameras())
        availableLenses = Self.deduplicate(dataStore.fetchLenses())
    }

    private func reloadSelections(projectId: String) {
        selectedCameraIds = Set(selectionStore.cameraIds(for: projectId))
        selectedLensIds = Set(selectionStore.lensIds(for: projectId))
    }
}
