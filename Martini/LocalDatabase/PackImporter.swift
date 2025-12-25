import Foundation

struct PackImporter {
    static func importPackIfNeeded() {
        let database = LocalDatabase.shared
        guard let url = Bundle.main.url(forResource: "martini_core_pack", withExtension: "json") else {
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let payload = try JSONDecoder().decode(PackPayload.self, from: data)
            if let existingRevision = database.fetchPackRevision(packId: payload.pack.packId),
               existingRevision >= payload.pack.revision {
                return
            }
            database.importPack(payload)
        } catch {
            print("❌ Pack import failed: \(error.localizedDescription)")
        }
    }
}
