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
            sensor_height_mm REAL NOT NULL
        );
        """
        let createCameraModes = """
        CREATE TABLE IF NOT EXISTS camera_modes (
            id TEXT PRIMARY KEY,
            camera_id TEXT NOT NULL,
            name TEXT NOT NULL,
            sensor_width_mm REAL NOT NULL,
            sensor_height_mm REAL NOT NULL,
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
            is_zoom INTEGER NOT NULL
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

        [createPacks, createCameras, createCameraModes, createLenses, createLensPrefs, createIphoneCameras, createProjectCameras, createProjectLenses]
            .forEach(execute)
    }

    func seedIfNeeded() {
        guard countRows(in: "cameras") == 0 else { return }
        execute("INSERT OR REPLACE INTO packs (id, name, revision) VALUES ('core_pack', 'Core Pack', 1)")
        execute("INSERT OR REPLACE INTO cameras (id, brand, model, sensor_width_mm, sensor_height_mm) VALUES ('alexa_35', 'ARRI', 'ALEXA 35', 27.99, 19.22)")
        execute("INSERT OR REPLACE INTO camera_modes (id, camera_id, name, sensor_width_mm, sensor_height_mm) VALUES ('alexa_35_opengate', 'alexa_35', 'Open Gate 4.6K', 27.99, 19.22)")
        execute("INSERT OR REPLACE INTO lenses (id, brand, series, focal_min_mm, focal_max_mm, t_stop, squeeze, is_zoom) VALUES ('cooke_s4_i__35mm__t2_0__1x', 'Cooke', 'S4/i', 35, 35, 2.0, 1.0, 0)")
        execute("INSERT OR REPLACE INTO lenses (id, brand, series, focal_min_mm, focal_max_mm, t_stop, squeeze, is_zoom) VALUES ('angenieux_optimo__24-290mm__t2_8__1x', 'Angenieux', 'Optimo', 24, 290, 2.8, 1.0, 1)")
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
        execute("DELETE FROM project_cameras WHERE project_id = '\(projectId)'")
        for cameraId in cameraIds {
            let id = "\(projectId)_\(cameraId)"
            execute("INSERT OR REPLACE INTO project_cameras (id, project_id, camera_id) VALUES ('\(id)', '\(projectId)', '\(cameraId)')")
        }
    }

    func updateProjectLenses(projectId: String, lensIds: [String]) {
        execute("DELETE FROM project_lenses WHERE project_id = '\(projectId)'")
        for lensId in lensIds {
            let id = "\(projectId)_\(lensId)"
            execute("INSERT OR REPLACE INTO project_lenses (id, project_id, lens_id) VALUES ('\(id)', '\(projectId)', '\(lensId)')")
        }
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
}
