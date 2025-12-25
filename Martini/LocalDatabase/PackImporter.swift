import Foundation

struct PackImporter {
    static func importPackIfNeeded(using database: LocalDatabase) {
        guard let url = Bundle.main.url(forResource: "martini_core_pack", withExtension: "json") else {
            print("❌ Pack import failed: martini_core_pack.json not found in bundle")
            return
        }

        do {
            print("📦 Pack import starting from \(url.lastPathComponent)")
            let data = try Data(contentsOf: url)
            let payload = try JSONDecoder().decode(PackPayload.self, from: data)
            print("📦 Pack decode success: \(payload.cameras.count) cameras, \(payload.lenses.count) lenses, \(payload.lensPacks?.count ?? 0) lens packs, \(payload.lensPackItems?.count ?? 0) pack items")
            database.importPack(payload)
            print("✅ Pack import finished")
        } catch {
            print("❌ Pack import failed: \(error)")
        }
    }
}
