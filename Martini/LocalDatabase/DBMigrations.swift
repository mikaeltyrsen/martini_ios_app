import Foundation
import SQLite3

final class LocalDatabase {
    static let shared = LocalDatabase()

    private let databaseURL: URL
    private var db: OpaquePointer?

    private init() {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let folderURL = baseURL?.appendingPathComponent("Martini", isDirectory: true) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        databaseURL = folderURL.appendingPathComponent("martini.sqlite")
        openDatabase()
        migrateIfNeeded()
        seedIfNeeded()
        PackImporter.importPackIfNeeded(using: self)
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    private func openDatabase() {
        if sqlite3_open(databaseURL.path, &db) != SQLITE_OK {
            print("❌ Unable to open database at \(databaseURL.path)")
        }
    }

    private func execute(_ sql: String) {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) != SQLITE_DONE {
                print("❌ SQL execution failed: \(sql)")
            }
        } else {
            print("❌ SQL prepare failed: \(sql)")
        }
        sqlite3_finalize(statement)
    }

    func migrateIfNeeded() {
        let createPacks = """
        CREATE TABLE IF NOT EXISTS packs (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            revision INTEGER NOT NULL
        );
        """
        let createCameras = """
        CREATE TABLE IF NOT EXISTS cameras (
            id TEXT PRIMARY KEY,
            brand TEXT NOT NULL,
            model TEXT NOT NULL,
            sensor_width_mm REAL NOT NULL,
            sensor_height_mm REAL NOT NULL,
            sensor_type TEXT,
            mount TEXT
        );
        """
        let createCameraModes = """
        CREATE TABLE IF NOT EXISTS camera_modes (
            id TEXT PRIMARY KEY,
            camera_id TEXT NOT NULL,
            name TEXT NOT NULL,
            sensor_width_mm REAL NOT NULL,
            sensor_height_mm REAL NOT NULL,
            resolution TEXT,
            aspect_ratio TEXT,
            FOREIGN KEY(camera_id) REFERENCES cameras(id)
        );
        """
        let createLenses = """
        CREATE TABLE IF NOT EXISTS lenses (
            id TEXT PRIMARY KEY,
            brand TEXT NOT NULL,
            series TEXT NOT NULL,
            focal_min_mm REAL NOT NULL,
            focal_max_mm REAL NOT NULL,
            t_stop REAL NOT NULL,
            squeeze REAL NOT NULL,
            is_zoom INTEGER NOT NULL,
            format TEXT,
            mounts TEXT
        );
        """
        let createLensPacks = """
        CREATE TABLE IF NOT EXISTS lens_packs (
            id TEXT PRIMARY KEY,
            brand TEXT NOT NULL,
            name TEXT NOT NULL,
            type TEXT NOT NULL,
            format TEXT NOT NULL,
            description TEXT
        );
        """
        let createLensPackItems = """
        CREATE TABLE IF NOT EXISTS lens_pack_items (
            id TEXT PRIMARY KEY,
            pack_id TEXT NOT NULL,
            lens_id TEXT NOT NULL,
            sort_order INTEGER NOT NULL,
            FOREIGN KEY(pack_id) REFERENCES lens_packs(id),
            FOREIGN KEY(lens_id) REFERENCES lenses(id)
        );
        """
        let createLensPrefs = """
        CREATE TABLE IF NOT EXISTS lens_user_prefs (
            id TEXT PRIMARY KEY,
            lens_id TEXT NOT NULL,
            is_favorite INTEGER NOT NULL,
            FOREIGN KEY(lens_id) REFERENCES lenses(id)
        );
        """
        let createIphoneCameras = """
        CREATE TABLE IF NOT EXISTS iphone_cameras (
            id TEXT PRIMARY KEY,
            iphone_model TEXT NOT NULL,
            camera_role TEXT NOT NULL,
            native_hfov_deg REAL NOT NULL,
            min_zoom REAL NOT NULL,
            max_zoom REAL NOT NULL
        );
        """
        let createProjectCameras = """
        CREATE TABLE IF NOT EXISTS project_cameras (
            id TEXT PRIMARY KEY,
            project_id TEXT NOT NULL,
            camera_id TEXT NOT NULL,
            FOREIGN KEY(camera_id) REFERENCES cameras(id)
        );
        """
        let createProjectLenses = """
        CREATE TABLE IF NOT EXISTS project_lenses (
            id TEXT PRIMARY KEY,
            project_id TEXT NOT NULL,
            lens_id TEXT NOT NULL,
            FOREIGN KEY(lens_id) REFERENCES lenses(id)
        );
        """

        [createPacks, createCameras, createCameraModes, createLenses, createLensPrefs, createIphoneCameras, createProjectCameras, createProjectLenses, createLensPacks, createLensPackItems]
            .forEach(execute)

        ensureColumn(table: "cameras", column: "sensor_type", type: "TEXT")
        ensureColumn(table: "cameras", column: "mount", type: "TEXT")
        ensureColumn(table: "camera_modes", column: "resolution", type: "TEXT")
        ensureColumn(table: "camera_modes", column: "aspect_ratio", type: "TEXT")
        ensureColumn(table: "lenses", column: "format", type: "TEXT")
        ensureColumn(table: "lenses", column: "mounts", type: "TEXT")
    }

    func seedIfNeeded() {
        guard countRows(in: "iphone_cameras") == 0 else { return }
        execute("INSERT OR REPLACE INTO iphone_cameras (id, iphone_model, camera_role, native_hfov_deg, min_zoom, max_zoom) VALUES ('iphone_15_pro_ultra', 'iPhone 15 Pro', 'ultra', 120.0, 0.5, 1.0)")
        execute("INSERT OR REPLACE INTO iphone_cameras (id, iphone_model, camera_role, native_hfov_deg, min_zoom, max_zoom) VALUES ('iphone_15_pro_main', 'iPhone 15 Pro', 'main', 80.0, 1.0, 2.0)")
        execute("INSERT OR REPLACE INTO iphone_cameras (id, iphone_model, camera_role, native_hfov_deg, min_zoom, max_zoom) VALUES ('iphone_15_pro_tele', 'iPhone 15 Pro', 'tele', 40.0, 2.0, 6.0)")
    }

    private func countRows(in table: String) -> Int {
        let query = "SELECT COUNT(*) FROM \(table)"
        var statement: OpaquePointer?
        var count = 0
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                count = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)
        return count
    }

    func fetchCameras() -> [DBCamera] {
        let query = "SELECT id, brand, model, sensor_width_mm, sensor_height_mm FROM cameras ORDER BY brand, model"
        var statement: OpaquePointer?
        var results: [DBCamera] = []
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(statement, 0))
                let brand = String(cString: sqlite3_column_text(statement, 1))
                let model = String(cString: sqlite3_column_text(statement, 2))
                let width = sqlite3_column_double(statement, 3)
                let height = sqlite3_column_double(statement, 4)
                results.append(DBCamera(id: id, brand: brand, model: model, sensorWidthMm: width, sensorHeightMm: height))
            }
        }
        sqlite3_finalize(statement)
        return results
    }

    func fetchCameras(ids: [String]) -> [DBCamera] {
        guard !ids.isEmpty else { return [] }
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let query = "SELECT id, brand, model, sensor_width_mm, sensor_height_mm FROM cameras WHERE id IN (\(placeholders)) ORDER BY brand, model"
        var statement: OpaquePointer?
        var results: [DBCamera] = []
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            for (index, id) in ids.enumerated() {
                sqlite3_bind_text(statement, Int32(index + 1), id, -1, nil)
            }
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(statement, 0))
                let brand = String(cString: sqlite3_column_text(statement, 1))
                let model = String(cString: sqlite3_column_text(statement, 2))
                let width = sqlite3_column_double(statement, 3)
                let height = sqlite3_column_double(statement, 4)
                results.append(DBCamera(id: id, brand: brand, model: model, sensorWidthMm: width, sensorHeightMm: height))
            }
        }
        sqlite3_finalize(statement)
        return results
    }

    func fetchCameraModes(cameraId: String) -> [DBCameraMode] {
        let query = "SELECT id, camera_id, name, sensor_width_mm, sensor_height_mm FROM camera_modes WHERE camera_id = ? ORDER BY name"
        var statement: OpaquePointer?
        var results: [DBCameraMode] = []
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, cameraId, -1, nil)
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(statement, 0))
                let camId = String(cString: sqlite3_column_text(statement, 1))
                let name = String(cString: sqlite3_column_text(statement, 2))
                let width = sqlite3_column_double(statement, 3)
                let height = sqlite3_column_double(statement, 4)
                results.append(DBCameraMode(id: id, cameraId: camId, name: name, sensorWidthMm: width, sensorHeightMm: height))
            }
        }
        sqlite3_finalize(statement)
        return results
    }

    func fetchLenses() -> [DBLens] {
        let query = "SELECT id, brand, series, focal_min_mm, focal_max_mm, t_stop, squeeze, is_zoom FROM lenses ORDER BY brand, series"
        var statement: OpaquePointer?
        var results: [DBLens] = []
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(statement, 0))
                let brand = String(cString: sqlite3_column_text(statement, 1))
                let series = String(cString: sqlite3_column_text(statement, 2))
                let focalMin = sqlite3_column_double(statement, 3)
                let focalMax = sqlite3_column_double(statement, 4)
                let tStop = sqlite3_column_double(statement, 5)
                let squeeze = sqlite3_column_double(statement, 6)
                let isZoom = sqlite3_column_int(statement, 7) == 1
                results.append(DBLens(id: id, brand: brand, series: series, focalLengthMinMm: focalMin, focalLengthMaxMm: focalMax, tStop: tStop, squeeze: squeeze, isZoom: isZoom))
            }
        }
        sqlite3_finalize(statement)
        return results
    }

    func fetchLenses(ids: [String]) -> [DBLens] {
        guard !ids.isEmpty else { return [] }
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let query = "SELECT id, brand, series, focal_min_mm, focal_max_mm, t_stop, squeeze, is_zoom FROM lenses WHERE id IN (\(placeholders)) ORDER BY brand, series"
        var statement: OpaquePointer?
        var results: [DBLens] = []
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            for (index, id) in ids.enumerated() {
                sqlite3_bind_text(statement, Int32(index + 1), id, -1, nil)
            }
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(statement, 0))
                let brand = String(cString: sqlite3_column_text(statement, 1))
                let series = String(cString: sqlite3_column_text(statement, 2))
                let focalMin = sqlite3_column_double(statement, 3)
                let focalMax = sqlite3_column_double(statement, 4)
                let tStop = sqlite3_column_double(statement, 5)
                let squeeze = sqlite3_column_double(statement, 6)
                let isZoom = sqlite3_column_int(statement, 7) == 1
                results.append(DBLens(id: id, brand: brand, series: series, focalLengthMinMm: focalMin, focalLengthMaxMm: focalMax, tStop: tStop, squeeze: squeeze, isZoom: isZoom))
            }
        }
        sqlite3_finalize(statement)
        return results
    }

    func fetchIPhoneCameras(model: String) -> [DBIPhoneCamera] {
        let query = "SELECT id, iphone_model, camera_role, native_hfov_deg, min_zoom, max_zoom FROM iphone_cameras WHERE iphone_model = ?"
        var statement: OpaquePointer?
        var results: [DBIPhoneCamera] = []
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, model, -1, nil)
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(statement, 0))
                let iphoneModel = String(cString: sqlite3_column_text(statement, 1))
                let role = String(cString: sqlite3_column_text(statement, 2))
                let hfov = sqlite3_column_double(statement, 3)
                let minZoom = sqlite3_column_double(statement, 4)
                let maxZoom = sqlite3_column_double(statement, 5)
                results.append(DBIPhoneCamera(id: id, iphoneModel: iphoneModel, cameraRole: role, nativeHFOVDegrees: hfov, minZoom: minZoom, maxZoom: maxZoom))
            }
        }
        sqlite3_finalize(statement)
        return results
    }

    func updateProjectCameras(projectId: String, cameraIds: [String]) {
        execute("BEGIN TRANSACTION")
        execute("DELETE FROM project_cameras WHERE project_id = '\(projectId)'")
        let sql = "INSERT OR REPLACE INTO project_cameras (id, project_id, camera_id) VALUES (?, ?, ?)"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            for cameraId in cameraIds {
                let id = "\(projectId)_\(cameraId)"
                sqlite3_bind_text(statement, 1, id, -1, nil)
                sqlite3_bind_text(statement, 2, projectId, -1, nil)
                sqlite3_bind_text(statement, 3, cameraId, -1, nil)
                _ = sqlite3_step(statement)
                sqlite3_reset(statement)
            }
        }
        sqlite3_finalize(statement)
        execute("COMMIT")
    }

    func updateProjectLenses(projectId: String, lensIds: [String]) {
        execute("BEGIN TRANSACTION")
        execute("DELETE FROM project_lenses WHERE project_id = '\(projectId)'")
        let sql = "INSERT OR REPLACE INTO project_lenses (id, project_id, lens_id) VALUES (?, ?, ?)"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            for lensId in lensIds {
                let id = "\(projectId)_\(lensId)"
                sqlite3_bind_text(statement, 1, id, -1, nil)
                sqlite3_bind_text(statement, 2, projectId, -1, nil)
                sqlite3_bind_text(statement, 3, lensId, -1, nil)
                _ = sqlite3_step(statement)
                sqlite3_reset(statement)
            }
        }
        sqlite3_finalize(statement)
        execute("COMMIT")
    }

    func fetchProjectCameraIds(projectId: String) -> [String] {
        let query = "SELECT camera_id FROM project_cameras WHERE project_id = ?"
        var statement: OpaquePointer?
        var results: [String] = []
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, projectId, -1, nil)
            while sqlite3_step(statement) == SQLITE_ROW {
                results.append(String(cString: sqlite3_column_text(statement, 0)))
            }
        }
        sqlite3_finalize(statement)
        return results
    }

    func fetchProjectLensIds(projectId: String) -> [String] {
        let query = "SELECT lens_id FROM project_lenses WHERE project_id = ?"
        var statement: OpaquePointer?
        var results: [String] = []
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, projectId, -1, nil)
            while sqlite3_step(statement) == SQLITE_ROW {
                results.append(String(cString: sqlite3_column_text(statement, 0)))
            }
        }
        sqlite3_finalize(statement)
        return results
    }

    func fetchPackRevision(packId: String) -> Int? {
        let query = "SELECT revision FROM packs WHERE id = ?"
        var statement: OpaquePointer?
        var revision: Int?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, packId, -1, nil)
            if sqlite3_step(statement) == SQLITE_ROW {
                revision = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)
        return revision
    }

    func importPack(_ payload: PackPayload) {
        execute("BEGIN TRANSACTION")
        defer { execute("COMMIT") }

        upsertPack(id: payload.pack.packId, name: payload.pack.description, revision: payload.pack.revision)

        for camera in payload.cameras {
            guard let primaryMode = camera.modes.first else { continue }
            upsertCamera(
                id: camera.id,
                brand: camera.brand,
                model: camera.model,
                sensorWidthMm: primaryMode.sensorWidthMm,
                sensorHeightMm: primaryMode.sensorHeightMm,
                sensorType: camera.sensorType,
                mount: camera.mount
            )

            for mode in camera.modes {
                upsertCameraMode(
                    id: mode.id,
                    cameraId: camera.id,
                    name: mode.name,
                    sensorWidthMm: mode.sensorWidthMm,
                    sensorHeightMm: mode.sensorHeightMm,
                    resolution: mode.resolution,
                    aspectRatio: mode.aspectRatio
                )
            }
        }

        for pack in payload.lensPacks ?? [] {
            upsertLensPack(
                id: pack.id,
                brand: pack.brand,
                name: pack.name,
                type: pack.type,
                format: pack.format,
                description: pack.description
            )
        }

        for lens in payload.lenses {
            let isZoom = lens.type.lowercased() == "zoom" || lens.focalLengthMmMin != nil || lens.focalLengthMmMax != nil
            let focalMin = lens.focalLengthMmMin ?? lens.focalLengthMm ?? 0
            let focalMax = lens.focalLengthMmMax ?? lens.focalLengthMm ?? focalMin
            let focalLabel: String
            if isZoom {
                focalLabel = "\(Int(focalMin))-\(Int(focalMax))mm"
            } else {
                focalLabel = "\(Int(focalMin))mm"
            }
            let lensId = lens.id ?? LensIdBuilder.buildId(
                brand: lens.brand,
                series: lens.series,
                focal: focalLabel,
                tStop: lens.maxTStop,
                squeeze: lens.squeeze
            )

            upsertLens(
                id: lensId,
                brand: lens.brand,
                series: lens.series,
                focalMinMm: focalMin,
                focalMaxMm: focalMax,
                tStop: lens.maxTStop,
                squeeze: lens.squeeze,
                isZoom: isZoom,
                format: lens.format,
                mounts: lens.mounts
            )
        }

        for item in payload.lensPackItems ?? [] {
            guard let lensId = item.lensId, !lensId.isEmpty else { continue }
            let itemId = "\(item.packId)__\(lensId)"
            upsertLensPackItem(
                id: itemId,
                packId: item.packId,
                lensId: lensId,
                sortOrder: item.sortOrder
            )
        }
    }

    private func upsertPack(id: String, name: String, revision: Int) {
        let sql = "INSERT OR REPLACE INTO packs (id, name, revision) VALUES (?, ?, ?)"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, id, -1, nil)
            sqlite3_bind_text(statement, 2, name, -1, nil)
            sqlite3_bind_int(statement, 3, Int32(revision))
            _ = sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }

    private func upsertCamera(id: String, brand: String, model: String, sensorWidthMm: Double, sensorHeightMm: Double, sensorType: String?, mount: String?) {
        let sql = "INSERT OR REPLACE INTO cameras (id, brand, model, sensor_width_mm, sensor_height_mm, sensor_type, mount) VALUES (?, ?, ?, ?, ?, ?, ?)"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, id, -1, nil)
            sqlite3_bind_text(statement, 2, brand, -1, nil)
            sqlite3_bind_text(statement, 3, model, -1, nil)
            sqlite3_bind_double(statement, 4, sensorWidthMm)
            sqlite3_bind_double(statement, 5, sensorHeightMm)
            sqlite3_bind_text(statement, 6, sensorType ?? "", -1, nil)
            sqlite3_bind_text(statement, 7, mount ?? "", -1, nil)
            _ = sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }

    private func upsertCameraMode(id: String, cameraId: String, name: String, sensorWidthMm: Double, sensorHeightMm: Double, resolution: String?, aspectRatio: String?) {
        let sql = "INSERT OR REPLACE INTO camera_modes (id, camera_id, name, sensor_width_mm, sensor_height_mm, resolution, aspect_ratio) VALUES (?, ?, ?, ?, ?, ?, ?)"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, id, -1, nil)
            sqlite3_bind_text(statement, 2, cameraId, -1, nil)
            sqlite3_bind_text(statement, 3, name, -1, nil)
            sqlite3_bind_double(statement, 4, sensorWidthMm)
            sqlite3_bind_double(statement, 5, sensorHeightMm)
            sqlite3_bind_text(statement, 6, resolution ?? "", -1, nil)
            sqlite3_bind_text(statement, 7, aspectRatio ?? "", -1, nil)
            _ = sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }

    private func upsertLens(id: String, brand: String, series: String, focalMinMm: Double, focalMaxMm: Double, tStop: Double, squeeze: Double, isZoom: Bool, format: String?, mounts: [String]?) {
        let sql = "INSERT OR REPLACE INTO lenses (id, brand, series, focal_min_mm, focal_max_mm, t_stop, squeeze, is_zoom, format, mounts) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, id, -1, nil)
            sqlite3_bind_text(statement, 2, brand, -1, nil)
            sqlite3_bind_text(statement, 3, series, -1, nil)
            sqlite3_bind_double(statement, 4, focalMinMm)
            sqlite3_bind_double(statement, 5, focalMaxMm)
            sqlite3_bind_double(statement, 6, tStop)
            sqlite3_bind_double(statement, 7, squeeze)
            sqlite3_bind_int(statement, 8, isZoom ? 1 : 0)
            sqlite3_bind_text(statement, 9, format ?? "", -1, nil)
            let mountsValue = mounts?.joined(separator: ",") ?? ""
            sqlite3_bind_text(statement, 10, mountsValue, -1, nil)
            _ = sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }

    private func upsertLensPack(id: String, brand: String, name: String, type: String, format: String, description: String) {
        let sql = "INSERT OR REPLACE INTO lens_packs (id, brand, name, type, format, description) VALUES (?, ?, ?, ?, ?, ?)"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, id, -1, nil)
            sqlite3_bind_text(statement, 2, brand, -1, nil)
            sqlite3_bind_text(statement, 3, name, -1, nil)
            sqlite3_bind_text(statement, 4, type, -1, nil)
            sqlite3_bind_text(statement, 5, format, -1, nil)
            sqlite3_bind_text(statement, 6, description, -1, nil)
            _ = sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }

    private func upsertLensPackItem(id: String, packId: String, lensId: String, sortOrder: Int) {
        let sql = "INSERT OR REPLACE INTO lens_pack_items (id, pack_id, lens_id, sort_order) VALUES (?, ?, ?, ?)"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, id, -1, nil)
            sqlite3_bind_text(statement, 2, packId, -1, nil)
            sqlite3_bind_text(statement, 3, lensId, -1, nil)
            sqlite3_bind_int(statement, 4, Int32(sortOrder))
            _ = sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }

    private func ensureColumn(table: String, column: String, type: String) {
        let query = "PRAGMA table_info(\(table))"
        var statement: OpaquePointer?
        var exists = false
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let name = String(cString: sqlite3_column_text(statement, 1))
                if name == column {
                    exists = true
                    break
                }
            }
        }
        sqlite3_finalize(statement)
        guard !exists else { return }
        execute("ALTER TABLE \(table) ADD COLUMN \(column) \(type)")
    }
}
