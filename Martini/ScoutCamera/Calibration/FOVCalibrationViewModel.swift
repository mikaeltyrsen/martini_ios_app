import Foundation

struct FOVCalibrationModule: Identifiable, Hashable {
    let role: String

    var id: String { role }
    var displayName: String { Self.displayName(for: role) }

    static func displayName(for role: String) -> String {
        switch role {
        case "ultra":
            return "Ultra"
        case "tele":
            return "Tele"
        case "main":
            return "Main"
        default:
            return role.capitalized
        }
    }
}

final class FOVCalibrationViewModel: ObservableObject {
    @Published var modules: [FOVCalibrationModule] = []

    let store: FOVCalibrationStore

    init(store: FOVCalibrationStore, dataStore: LocalJSONStore = .shared) {
        self.store = store
        loadModules(from: dataStore)
    }

    func reset(role: String) {
        store.resetMultiplier(for: role)
    }

    func resetAll() {
        store.resetAll(roles: modules.map(\.role))
    }

    private func loadModules(from dataStore: LocalJSONStore) {
        let roles = Set(dataStore.fetchIPhoneCameras().map(\.cameraRole))
        let orderedRoles = orderRoles(Array(roles))
        modules = orderedRoles.map { FOVCalibrationModule(role: $0) }
    }

    private func orderRoles(_ roles: [String]) -> [String] {
        let preferred = ["ultra", "main", "tele"]
        let remaining = roles.filter { !preferred.contains($0) }.sorted()
        return preferred.filter { roles.contains($0) } + remaining
    }
}
