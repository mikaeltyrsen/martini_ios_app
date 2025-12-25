import Foundation

struct PackImporter {
    static func importPackIfNeeded(using database: LocalDatabase) {
        guard let url = Bundle.main.url(forResource: "martini_core_pack", withExtension: "json") else {
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let payload = try JSONDecoder().decode(PackPayload.self, from: data)
            database.importPack(payload)
        } catch {
            print("❌ Pack import failed: \(error.localizedDescription)")
        }
    }
}
