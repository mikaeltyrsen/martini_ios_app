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
        execute("PRAGMA foreign_keys = ON;")
        ["lens_pack_items", "lens_packs", "project_cameras", "project_lenses", "project_scout_last_selection", "camera_modes", "cameras", "lenses", "lens_user_prefs", "iphone_cameras", "packs"]
            .forEach { execute("DROP TABLE IF EXISTS \($0);") }

        let createPacks = """
        CREATE TABLE IF NOT EXISTS packs (
          pack_id TEXT PRIMARY KEY,
          revision INTEGER NOT NULL,
          created_at TEXT,
          description TEXT,
          installed_at TEXT NOT NULL
        );
        """
        let createCameras = """
        CREATE TABLE IF NOT EXISTS cameras (
          id TEXT PRIMARY KEY,
          brand TEXT NOT NULL,
          model TEXT NOT NULL,
          sensor_type TEXT,
          mount TEXT,
          source_pack_id TEXT,
          source_revision INTEGER,
          created_at TEXT,
          updated_at TEXT
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
          source_pack_id TEXT,
          source_revision INTEGER,
          created_at TEXT,
          updated_at TEXT,
          FOREIGN KEY(camera_id) REFERENCES cameras(id) ON DELETE CASCADE
        );
        """
        let createLensPacks = """
        CREATE TABLE IF NOT EXISTS lens_packs (
          id TEXT PRIMARY KEY,
          brand TEXT NOT NULL,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          format TEXT,
          description TEXT,
          source_pack_id TEXT,
          source_revision INTEGER,
          created_at TEXT,
          updated_at TEXT
        );
        """
        let createLenses = """
        CREATE TABLE IF NOT EXISTS lenses (
          id TEXT PRIMARY KEY,
          type TEXT NOT NULL,
          brand TEXT NOT NULL,
          series TEXT NOT NULL,
          format TEXT,
          mounts_json TEXT,
          focal_length_mm REAL,
          focal_length_mm_min REAL,
          focal_length_mm_max REAL,
          max_t_stop REAL,
          squeeze REAL NOT NULL DEFAULT 1.0,
          tags_json TEXT,
          source_pack_id TEXT,
          source_revision INTEGER,
          created_at TEXT,
          updated_at TEXT
        );
        """
        let createLensPackItems = """
        CREATE TABLE IF NOT EXISTS lens_pack_items (
          pack_id TEXT NOT NULL,
          lens_id TEXT NOT NULL,
          sort_order INTEGER,
          PRIMARY KEY(pack_id, lens_id),
          FOREIGN KEY(pack_id) REFERENCES lens_packs(id) ON DELETE CASCADE,
          FOREIGN KEY(lens_id) REFERENCES lenses(id) ON DELETE CASCADE
        );
        """
        let createLensPrefs = """
        CREATE TABLE IF NOT EXISTS lens_user_prefs (
          lens_id TEXT PRIMARY KEY,
          is_favorite INTEGER NOT NULL DEFAULT 0,
          user_label TEXT,
          is_hidden INTEGER NOT NULL DEFAULT 0,
          last_used_at TEXT,
          FOREIGN KEY(lens_id) REFERENCES lenses(id) ON DELETE CASCADE
        );
        """
        let createIphoneCameras = """
        CREATE TABLE IF NOT EXISTS iphone_cameras (
          id TEXT PRIMARY KEY,
          hardware_id TEXT,
          iphone_model TEXT NOT NULL,
          camera_role TEXT NOT NULL,
          native_hfov_deg REAL NOT NULL,
          native_vfov_deg REAL,
          min_zoom REAL NOT NULL DEFAULT 1.0,
          max_zoom REAL NOT NULL DEFAULT 15.0
        );
        """
        let createProjectCameras = """
        CREATE TABLE IF NOT EXISTS project_cameras (
          project_id TEXT NOT NULL,
          camera_id TEXT NOT NULL,
          default_mode_id TEXT,
          PRIMARY KEY(project_id, camera_id),
          FOREIGN KEY(camera_id) REFERENCES cameras(id) ON DELETE CASCADE,
          FOREIGN KEY(default_mode_id) REFERENCES camera_modes(id) ON DELETE SET NULL
        );
        """
        let createProjectLenses = """
        CREATE TABLE IF NOT EXISTS project_lenses (
          project_id TEXT NOT NULL,
          lens_id TEXT NOT NULL,
          PRIMARY KEY(project_id, lens_id),
          FOREIGN KEY(lens_id) REFERENCES lenses(id) ON DELETE CASCADE
        );
        """
        let createProjectScoutSelection = """
        CREATE TABLE IF NOT EXISTS project_scout_last_selection (
          project_id TEXT PRIMARY KEY,
          camera_id TEXT,
          mode_id TEXT,
          lens_id TEXT,
          zoom_focal_length_mm REAL,
          updated_at TEXT,
          FOREIGN KEY(camera_id) REFERENCES cameras(id) ON DELETE SET NULL,
          FOREIGN KEY(mode_id) REFERENCES camera_modes(id) ON DELETE SET NULL,
          FOREIGN KEY(lens_id) REFERENCES lenses(id) ON DELETE SET NULL
        );
        """

        [createPacks, createCameras, createCameraModes, createLensPacks, createLenses, createLensPackItems, createLensPrefs, createIphoneCameras, createProjectCameras, createProjectLenses, createProjectScoutSelection]
            .forEach(execute)
    }

    func seedIfNeeded() {
        return
    }

    func countRows(in table: String) -> Int {
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
        let query = """
        SELECT
          cameras.id,
          cameras.brand,
          cameras.model,
          cameras.sensor_type,
          cameras.mount,
          (SELECT sensor_width_mm FROM camera_modes WHERE camera_id = cameras.id ORDER BY name LIMIT 1) AS sensor_width_mm,
          (SELECT sensor_height_mm FROM camera_modes WHERE camera_id = cameras.id ORDER BY name LIMIT 1) AS sensor_height_mm
        FROM cameras
        ORDER BY brand, model
        """
        var statement: OpaquePointer?
        var results: [DBCamera] = []
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(statement, 0))
                let brand = String(cString: sqlite3_column_text(statement, 1))
                let model = String(cString: sqlite3_column_text(statement, 2))
                let sensorType = sqlite3_column_type(statement, 3) == SQLITE_NULL
                    ? nil
                    : String(cString: sqlite3_column_text(statement, 3))
                let mount = sqlite3_column_type(statement, 4) == SQLITE_NULL
                    ? nil
                    : String(cString: sqlite3_column_text(statement, 4))
                let width = sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 5)
                let height = sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 6)
                results.append(DBCamera(id: id, brand: brand, model: model, sensorType: sensorType, mount: mount, sensorWidthMm: width, sensorHeightMm: height))
            }
        }
        sqlite3_finalize(statement)
        return results
    }

    func fetchCameras(ids: [String]) -> [DBCamera] {
        guard !ids.isEmpty else { return [] }
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let query = """
        SELECT
          cameras.id,
          cameras.brand,
          cameras.model,
          cameras.sensor_type,
          cameras.mount,
          (SELECT sensor_width_mm FROM camera_modes WHERE camera_id = cameras.id ORDER BY name LIMIT 1) AS sensor_width_mm,
          (SELECT sensor_height_mm FROM camera_modes WHERE camera_id = cameras.id ORDER BY name LIMIT 1) AS sensor_height_mm
        FROM cameras
        WHERE cameras.id IN (\(placeholders))
        ORDER BY brand, model
        """
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
                let sensorType = sqlite3_column_type(statement, 3) == SQLITE_NULL
                    ? nil
                    : String(cString: sqlite3_column_text(statement, 3))
                let mount = sqlite3_column_type(statement, 4) == SQLITE_NULL
                    ? nil
                    : String(cString: sqlite3_column_text(statement, 4))
                let width = sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 5)
                let height = sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 6)
                results.append(DBCamera(id: id, brand: brand, model: model, sensorType: sensorType, mount: mount, sensorWidthMm: width, sensorHeightMm: height))
            }
        }
        sqlite3_finalize(statement)
        return results
    }

    func fetchCameraModes(cameraId: String) -> [DBCameraMode] {
        let query = "SELECT id, camera_id, name, sensor_width_mm, sensor_height_mm, resolution, aspect_ratio FROM camera_modes WHERE camera_id = ? ORDER BY name"
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
                let resolution = sqlite3_column_type(statement, 5) == SQLITE_NULL
                    ? nil
                    : String(cString: sqlite3_column_text(statement, 5))
                let aspectRatio = sqlite3_column_type(statement, 6) == SQLITE_NULL
                    ? nil
                    : String(cString: sqlite3_column_text(statement, 6))
                results.append(DBCameraMode(id: id, cameraId: camId, name: name, sensorWidthMm: width, sensorHeightMm: height, resolution: resolution, aspectRatio: aspectRatio))
            }
        }
        sqlite3_finalize(statement)
        return results
    }

    func fetchLenses() -> [DBLens] {
        let query = """
        SELECT id, type, brand, series, format, mounts_json, focal_length_mm, focal_length_mm_min, focal_length_mm_max, max_t_stop, squeeze
        FROM lenses
        ORDER BY brand, series
        """
        var statement: OpaquePointer?
        var results: [DBLens] = []
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(statement, 0))
                let type = String(cString: sqlite3_column_text(statement, 1))
                let brand = String(cString: sqlite3_column_text(statement, 2))
                let series = String(cString: sqlite3_column_text(statement, 3))
                let format = sqlite3_column_type(statement, 4) == SQLITE_NULL
                    ? nil
                    : String(cString: sqlite3_column_text(statement, 4))
                let mountsValue = sqlite3_column_type(statement, 5) == SQLITE_NULL
                    ? ""
                    : String(cString: sqlite3_column_text(statement, 5))
                let mounts = mountsValue.split(separator: ",").map { String($0) }.filter { !$0.isEmpty }
                let focalLengthMm = sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 6)
                let focalLengthMinMm = sqlite3_column_type(statement, 7) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 7)
                let focalLengthMaxMm = sqlite3_column_type(statement, 8) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 8)
                let maxTStop = sqlite3_column_double(statement, 9)
                let squeeze = sqlite3_column_double(statement, 10)
                results.append(DBLens(
                    id: id,
                    type: type,
                    brand: brand,
                    series: series,
                    format: format,
                    mounts: mounts,
                    focalLengthMm: focalLengthMm,
                    focalLengthMinMm: focalLengthMinMm,
                    focalLengthMaxMm: focalLengthMaxMm,
                    maxTStop: maxTStop,
                    squeeze: squeeze
                ))
            }
        }
        sqlite3_finalize(statement)
        return results
    }

    func fetchLenses(ids: [String]) -> [DBLens] {
        guard !ids.isEmpty else { return [] }
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let query = """
        SELECT id, type, brand, series, format, mounts_json, focal_length_mm, focal_length_mm_min, focal_length_mm_max, max_t_stop, squeeze
        FROM lenses
        WHERE id IN (\(placeholders))
        ORDER BY brand, series
        """
        var statement: OpaquePointer?
        var results: [DBLens] = []
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            for (index, id) in ids.enumerated() {
                sqlite3_bind_text(statement, Int32(index + 1), id, -1, nil)
            }
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(statement, 0))
                let type = String(cString: sqlite3_column_text(statement, 1))
                let brand = String(cString: sqlite3_column_text(statement, 2))
                let series = String(cString: sqlite3_column_text(statement, 3))
                let format = sqlite3_column_type(statement, 4) == SQLITE_NULL
                    ? nil
                    : String(cString: sqlite3_column_text(statement, 4))
                let mountsValue = sqlite3_column_type(statement, 5) == SQLITE_NULL
                    ? ""
                    : String(cString: sqlite3_column_text(statement, 5))
                let mounts = mountsValue.split(separator: ",").map { String($0) }.filter { !$0.isEmpty }
                let focalLengthMm = sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 6)
                let focalLengthMinMm = sqlite3_column_type(statement, 7) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 7)
                let focalLengthMaxMm = sqlite3_column_type(statement, 8) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 8)
                let maxTStop = sqlite3_column_double(statement, 9)
                let squeeze = sqlite3_column_double(statement, 10)
                results.append(DBLens(
                    id: id,
                    type: type,
                    brand: brand,
                    series: series,
                    format: format,
                    mounts: mounts,
                    focalLengthMm: focalLengthMm,
                    focalLengthMinMm: focalLengthMinMm,
                    focalLengthMaxMm: focalLengthMaxMm,
                    maxTStop: maxTStop,
                    squeeze: squeeze
                ))
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

        execute("DELETE FROM lens_pack_items")
        execute("DELETE FROM lens_packs")
        execute("DELETE FROM camera_modes")
        execute("DELETE FROM cameras")
        execute("DELETE FROM lenses")
        execute("DELETE FROM packs")

        upsertPack(id: payload.pack.packId, name: payload.pack.description, revision: payload.pack.revision)

        for camera in payload.cameras {
            if camera.id == payload.cameras.first?.id {
                print("📦 Pack camera sample: \(camera.brand) \(camera.model)")
            }
            guard !camera.modes.isEmpty else { continue }
            upsertCamera(
                id: camera.id,
                brand: camera.brand,
                model: camera.model,
                sensorType: camera.sensorType,
                mount: camera.mount,
                sourcePackId: payload.pack.packId,
                sourceRevision: payload.pack.revision
            )

            for mode in camera.modes {
                upsertCameraMode(
                    id: mode.id,
                    cameraId: camera.id,
                    name: mode.name,
                    sensorWidthMm: mode.sensorWidthMm,
                    sensorHeightMm: mode.sensorHeightMm,
                    resolution: mode.resolution,
                    aspectRatio: mode.aspectRatio,
                    sourcePackId: payload.pack.packId,
                    sourceRevision: payload.pack.revision
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
                description: pack.description,
                sourcePackId: payload.pack.packId,
                sourceRevision: payload.pack.revision
            )
        }

        for lens in payload.lenses {
            if lens.id == payload.lenses.first?.id {
                print("📦 Pack lens sample: \(lens.brand) \(lens.series)")
            }
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
                type: lens.type,
                brand: lens.brand,
                series: lens.series,
                format: lens.format,
                mounts: lens.mounts,
                focalLengthMm: lens.focalLengthMm,
                focalLengthMinMm: lens.focalLengthMmMin,
                focalLengthMaxMm: lens.focalLengthMmMax,
                maxTStop: lens.maxTStop,
                squeeze: lens.squeeze,
                sourcePackId: payload.pack.packId,
                sourceRevision: payload.pack.revision
            )
        }

        for item in payload.lensPackItems ?? [] {
            guard let lensId = item.lensId, !lensId.isEmpty else { continue }
            upsertLensPackItem(
                packId: item.packId,
                lensId: lensId,
                sortOrder: item.sortOrder
            )
        }

        let cameras = fetchCameras()
        let lenses = fetchLenses()
        print("🧪 Pack SQL check: \(cameras.count) cameras, \(lenses.count) lenses, \(countRows(in: "camera_modes")) modes")
        for camera in cameras.prefix(5) {
            print("  🎥 \(camera.brand) \(camera.model)")
        }
        for lens in lenses.prefix(5) {
            print("  🔭 \(lens.brand) \(lens.series) \(lens.focalLengthMinMm)–\(lens.focalLengthMaxMm)mm")
        }
    }

    private func upsertPack(id: String, name: String, revision: Int) {
        let sql = "INSERT OR REPLACE INTO packs (pack_id, revision, created_at, description, installed_at) VALUES (?, ?, ?, ?, ?)"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, id, -1, nil)
            sqlite3_bind_int(statement, 2, Int32(revision))
            sqlite3_bind_text(statement, 3, "", -1, nil)
            sqlite3_bind_text(statement, 4, name, -1, nil)
            let installedAt = ISO8601DateFormatter().string(from: Date())
            sqlite3_bind_text(statement, 5, installedAt, -1, nil)
            _ = sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }

    private func upsertCamera(id: String, brand: String, model: String, sensorType: String?, mount: String?, sourcePackId: String, sourceRevision: Int) {
        let sql = "INSERT OR REPLACE INTO cameras (id, brand, model, sensor_type, mount, source_pack_id, source_revision, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, id, -1, nil)
            sqlite3_bind_text(statement, 2, brand, -1, nil)
            sqlite3_bind_text(statement, 3, model, -1, nil)
            sqlite3_bind_text(statement, 4, sensorType ?? "", -1, nil)
            sqlite3_bind_text(statement, 5, mount ?? "", -1, nil)
            sqlite3_bind_text(statement, 6, sourcePackId, -1, nil)
            sqlite3_bind_int(statement, 7, Int32(sourceRevision))
            sqlite3_bind_text(statement, 8, "", -1, nil)
            sqlite3_bind_text(statement, 9, "", -1, nil)
            _ = sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }

    private func upsertCameraMode(id: String, cameraId: String, name: String, sensorWidthMm: Double, sensorHeightMm: Double, resolution: String?, aspectRatio: String?, sourcePackId: String, sourceRevision: Int) {
        let sql = "INSERT OR REPLACE INTO camera_modes (id, camera_id, name, sensor_width_mm, sensor_height_mm, resolution, aspect_ratio, source_pack_id, source_revision, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, id, -1, nil)
            sqlite3_bind_text(statement, 2, cameraId, -1, nil)
            sqlite3_bind_text(statement, 3, name, -1, nil)
            sqlite3_bind_double(statement, 4, sensorWidthMm)
            sqlite3_bind_double(statement, 5, sensorHeightMm)
            sqlite3_bind_text(statement, 6, resolution ?? "", -1, nil)
            sqlite3_bind_text(statement, 7, aspectRatio ?? "", -1, nil)
            sqlite3_bind_text(statement, 8, sourcePackId, -1, nil)
            sqlite3_bind_int(statement, 9, Int32(sourceRevision))
            sqlite3_bind_text(statement, 10, "", -1, nil)
            sqlite3_bind_text(statement, 11, "", -1, nil)
            _ = sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }

    private func upsertLens(id: String, type: String, brand: String, series: String, format: String?, mounts: [String]?, focalLengthMm: Double?, focalLengthMinMm: Double?, focalLengthMaxMm: Double?, maxTStop: Double, squeeze: Double, sourcePackId: String, sourceRevision: Int) {
        let sql = "INSERT OR REPLACE INTO lenses (id, type, brand, series, format, mounts_json, focal_length_mm, focal_length_mm_min, focal_length_mm_max, max_t_stop, squeeze, source_pack_id, source_revision, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, id, -1, nil)
            sqlite3_bind_text(statement, 2, type, -1, nil)
            sqlite3_bind_text(statement, 3, brand, -1, nil)
            sqlite3_bind_text(statement, 4, series, -1, nil)
            sqlite3_bind_text(statement, 5, format ?? "", -1, nil)
            let mountsValue = mounts?.joined(separator: ",") ?? ""
            sqlite3_bind_text(statement, 6, mountsValue, -1, nil)
            sqlite3_bind_double(statement, 7, focalLengthMm ?? 0)
            sqlite3_bind_double(statement, 8, focalLengthMinMm ?? 0)
            sqlite3_bind_double(statement, 9, focalLengthMaxMm ?? 0)
            sqlite3_bind_double(statement, 10, maxTStop)
            sqlite3_bind_double(statement, 11, squeeze)
            sqlite3_bind_text(statement, 12, sourcePackId, -1, nil)
            sqlite3_bind_int(statement, 13, Int32(sourceRevision))
            sqlite3_bind_text(statement, 14, "", -1, nil)
            sqlite3_bind_text(statement, 15, "", -1, nil)
            _ = sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }

    private func upsertLensPack(id: String, brand: String, name: String, type: String, format: String, description: String, sourcePackId: String, sourceRevision: Int) {
        let sql = "INSERT OR REPLACE INTO lens_packs (id, brand, name, type, format, description, source_pack_id, source_revision, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, id, -1, nil)
            sqlite3_bind_text(statement, 2, brand, -1, nil)
            sqlite3_bind_text(statement, 3, name, -1, nil)
            sqlite3_bind_text(statement, 4, type, -1, nil)
            sqlite3_bind_text(statement, 5, format, -1, nil)
            sqlite3_bind_text(statement, 6, description, -1, nil)
            sqlite3_bind_text(statement, 7, sourcePackId, -1, nil)
            sqlite3_bind_int(statement, 8, Int32(sourceRevision))
            sqlite3_bind_text(statement, 9, "", -1, nil)
            sqlite3_bind_text(statement, 10, "", -1, nil)
            _ = sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }

    private func upsertLensPackItem(packId: String, lensId: String, sortOrder: Int) {
        let sql = "INSERT OR REPLACE INTO lens_pack_items (pack_id, lens_id, sort_order) VALUES (?, ?, ?)"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, packId, -1, nil)
            sqlite3_bind_text(statement, 2, lensId, -1, nil)
            sqlite3_bind_int(statement, 3, Int32(sortOrder))
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
