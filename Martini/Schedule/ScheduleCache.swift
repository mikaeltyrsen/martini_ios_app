import Foundation

/// Persists fetched schedules so they can be reused between launches.
final class ScheduleCache {
    static let shared = ScheduleCache()

    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    private init() {
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        cacheDirectory = cachesDirectory.appendingPathComponent("ScheduleCache", isDirectory: true)

        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }

    func cachedSchedule(withId id: String) -> ProjectSchedule? {
        let url = cacheFileURL(for: id)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? JSONDecoder().decode(ProjectSchedule.self, from: data)
    }

    func store(schedule: ProjectSchedule) {
        let url = cacheFileURL(for: schedule.id)
        guard let data = try? JSONEncoder().encode(schedule) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func clear(exceptId id: String? = nil) {
        guard let contents = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else {
            return
        }

        for fileURL in contents {
            if let id = id, fileURL.lastPathComponent == "\(id).json" { continue }
            try? fileManager.removeItem(at: fileURL)
        }
    }

    private func cacheFileURL(for id: String) -> URL {
        cacheDirectory.appendingPathComponent("\(id).json")
    }
}
