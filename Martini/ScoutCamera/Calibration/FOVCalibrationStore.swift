import Foundation
import Darwin

final class FOVCalibrationStore: ObservableObject {
    static let shared = FOVCalibrationStore()

    @Published private(set) var multipliers: [String: Double]

    private let defaults: UserDefaults
    private let storageKey = "fovCalibrationMultipliersByDevice"
    private let hardwareId: String
    private var storage: CalibrationStorage

    init(userDefaults: UserDefaults = .standard, hardwareId: String? = FOVCalibrationStore.currentHardwareId()) {
        defaults = userDefaults
        self.hardwareId = hardwareId ?? "unknown"
        storage = CalibrationStorage.load(from: userDefaults, key: storageKey)
        multipliers = storage.devices[self.hardwareId] ?? [:]
    }

    func multiplier(for role: String) -> Double {
        multipliers[role] ?? 1.0
    }

    func setMultiplier(_ value: Double, for role: String) {
        multipliers[role] = value
        persist()
    }

    func resetMultiplier(for role: String) {
        multipliers[role] = 1.0
        persist()
    }

    func resetAll(roles: [String]) {
        roles.forEach { multipliers[$0] = 1.0 }
        persist()
    }

    private func persist() {
        storage.devices[hardwareId] = multipliers
        storage.save(to: defaults, key: storageKey)
    }

    private static func currentHardwareId() -> String? {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }
}

private struct CalibrationStorage: Codable {
    var devices: [String: [String: Double]]

    static func load(from defaults: UserDefaults, key: String) -> CalibrationStorage {
        guard let data = defaults.data(forKey: key),
              let storage = try? JSONDecoder().decode(CalibrationStorage.self, from: data) else {
            return CalibrationStorage(devices: [:])
        }
        return storage
    }

    func save(to defaults: UserDefaults, key: String) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: key)
    }
}
